import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/net_message.dart';
import 'net_protocol.dart';
import 'net_session.dart';

/// 局域网房间 - 房主端服务
/// 职责：TCP 监听（端口占用自动顺延）、hello 握手与座位分配、
/// 座位列表维护、玩家加入/离开广播、满员自动广播开局，
/// 以及 UDP 房间发现应答（客户端「联机」页的房间列表数据来源）。
/// 房主自己是玩家 1（本机，无网络会话），客户端依次占用玩家 2..N。
/// 对局消息（单词校验与广播）由步骤 4 的游戏层接入，本类只管房间生命周期。
class RoomHost extends ChangeNotifier {
  RoomHost({
    required this.gameName,
    required this.capacity,
    this.basePort = defaultPort,
  }) : assert(capacity >= 2, '房间至少 2 人');

  /// 游戏名称（等待页与房间列表展示用，如「单词PK」）
  final String gameName;

  /// 本局总人数（2-8，含房主）
  final int capacity;

  /// 监听起始端口：绑定失败自动尝试 +1（最多 10 个候选）；
  /// 测试可传 0 让系统分配临时端口，避免与真实端口冲突
  final int basePort;

  /// 默认 TCP 监听端口（避开常见服务端口，减少被占用概率）
  static const int defaultPort = 45654;

  /// 房间发现 UDP 固定端口：客户端只向固定端口广播探测，
  /// 因此不能像 TCP 那样顺延；同设备建第二个房间时 UDP 起不来，
  /// 房间仍可正常游玩但不会出现在他人的房间列表中（当前 UI 单房间场景不受影响）
  static const int discoveryPort = 45655;

  ServerSocket? _server;

  /// UDP 发现应答 socket（start 成功后创建）
  RawDatagramSocket? _discoverySocket;

  /// 已入座的客户端：座位号 -> 会话（座位 1 为房主本机，不在此表）
  final Map<int, NetSession> _clients = {};

  /// 实际监听端口（start 成功后有效；basePort 为 0 时是系统分配值）
  int _port = 0;
  int get port => _port;

  /// 是否已满员并广播过开局
  bool _gameStarted = false;
  bool get gameStarted => _gameStarted;

  /// 房间是否已关闭（房主主动解散）
  bool _closed = false;
  bool get closed => _closed;

  /// 当前已占用的座位（含房主的 1 号位），升序
  List<int> get seats => [1, ..._clients.keys.toList()..sort()];

  /// 是否满员
  bool get isFull => seats.length >= capacity;

  /// 启动监听；所有候选端口都被占用时返回 false
  Future<bool> start() async {
    for (var port = basePort; port < basePort + 10; port++) {
      try {
        final server = await ServerSocket.bind('0.0.0.0', port);
        _server = server;
        _port = server.port;
        // 只处理接入的连接；监听异常（端口被抢占等极端场景）交由各会话自行断开
        server.listen(_onAccept);
        await _startDiscovery();
        notifyListeners();
        return true;
      } on SocketException {
        // 端口被占用，尝试下一个
        continue;
      }
    }
    return false;
  }

  /// 启动 UDP 发现应答：监听固定端口，收到探测请求即单播回房间信息
  /// 监听失败（端口被同设备其他房间占用）时静默降级——房间可玩但不可发现
  Future<void> _startDiscovery() async {
    try {
      final socket = await RawDatagramSocket.bind(
        '0.0.0.0',
        discoveryPort,
      );
      _discoverySocket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        _onDiscoveryDatagram(socket, datagram);
      });
    } on SocketException {
      // UDP 端口被占用：放弃发现应答，不影响 TCP 房间功能
      _discoverySocket = null;
    }
  }

  /// 处理发现探测：校验为合法 discoveryRequest 后应答本房间信息
  /// UDP 包按独立数据报处理（直接 JSON 解码，不走 TCP 分帧器）；
  /// 坏包/异版消息直接忽略——UDP 本就允许丢包，客户端靠周期重试兜底
  void _onDiscoveryDatagram(
    RawDatagramSocket socket,
    Datagram datagram,
  ) {
    try {
      final json = utf8.decode(datagram.data);
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return;
      final message = NetMessage.fromJson(decoded);
      if (message.type != NetMessageType.discoveryRequest) return;
      socket.send(
        NetProtocol.encode(
          NetMessage(
            type: NetMessageType.discoveryResponse,
            payload: {
              'gameName': gameName,
              'players': seats.length,
              'capacity': capacity,
              'tcpPort': _port,
            },
          ),
        ),
        datagram.address,
        datagram.port,
      );
    } catch (_) {
      // 解码失败或对端版本不符：忽略该探测包
    }
  }

  /// 停止 UDP 发现应答（随房间关闭）
  void _stopDiscovery() {
    _discoverySocket?.close();
    _discoverySocket = null;
  }

  /// 获取本机局域网 IPv4 地址（房主页展示给好友输入用）
  /// 未连接 Wi-Fi / 仅有蜂窝网络时返回 null
  static Future<String?> localIpv4() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        // 跳过回环地址，取第一个局域网地址
        if (!address.isLoopback) return address.address;
      }
    }
    return null;
  }

  /// 解散房间：断开所有已入座玩家（各自发送 bye），停止监听
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final sessions = List.of(_clients.values);
    _clients.clear();
    // 先发 bye 再关 socket；会话断开回调因 _closed 已置位而不再触发座位清理
    for (final session in sessions) {
      await session.close();
    }
    _stopDiscovery();
    await _server?.close();
    _server = null;
    notifyListeners();
  }

  /// 新连接接入：建立会话并等待 hello 握手，10 秒未握手则断开
  /// （防止空连接长期占用资源）
  void _onAccept(Socket socket) {
    if (_closed) {
      socket.destroy();
      return;
    }
    final session = NetSession(socket);
    var seat = 0; // 0 表示尚未握手入座
    Timer? helloTimeout = Timer(const Duration(seconds: 10), () {
      if (seat == 0) session.close();
    });

    session.onDisconnected = () {
      helloTimeout?.cancel();
      helloTimeout = null;
      // 已入座则清理座位并广播；被拒的连接（seat 为 0）无需处理
      if (seat != 0) _removeClient(seat);
    };

    session.messages.listen((message) {
      switch (message.type) {
        case NetMessageType.hello:
          if (seat != 0) return; // 忽略重复握手
          helloTimeout?.cancel();
          helloTimeout = null;
          seat = _handleHello(session);
        case NetMessageType.bye:
          // 客户端主动退出：bye 后 socket 关闭会触发 onDisconnected 统一清理
          break;
        default:
          // 对局消息（wordSubmit 等）由步骤 4 的游戏层处理，此处忽略
          break;
      }
    });
  }

  /// 处理握手：满员则拒绝并断开；否则分配最小空位、应答加入结果、
  /// 广播入座消息，返回分配的座位号（拒绝时返回 0）
  int _handleHello(NetSession session) {
    if (isFull) {
      session.send(
        const NetMessage(
          type: NetMessageType.joinResponse,
          payload: {'ok': false, 'reason': 'roomFull'},
        ),
      );
      session.close();
      return 0;
    }

    // 分配 2..N 中最小未占用座位（有人中途退出后新加入者补位）
    final taken = _clients.keys.toSet();
    var seat = 2;
    while (taken.contains(seat)) {
      seat++;
    }
    _clients[seat] = session;

    // 应答：自己的座位 + 房间总人数 + 当前所有已入座玩家（供等待页渲染）
    session.send(
      NetMessage(
        type: NetMessageType.joinResponse,
        payload: {
          'ok': true,
          'seat': seat,
          'capacity': capacity,
          'players': seats,
        },
      ),
    );
    // 广播给其余玩家（新加入者已通过 joinResponse 获知全量座位）
    _broadcast(
      NetMessage(
        type: NetMessageType.playerJoined,
        payload: {'seat': seat},
      ),
      except: session,
    );
    notifyListeners();

    // 满员自动开局（重开场景由步骤 4 控制，此处只广播一次）
    if (isFull && !_gameStarted) _startGame();
    return seat;
  }

  /// 满员开局：广播 gameStart，客户端进入「即将开始」状态
  void _startGame() {
    _gameStarted = true;
    _broadcast(
      NetMessage(
        type: NetMessageType.gameStart,
        payload: {'playerCount': capacity},
      ),
    );
    notifyListeners();
    // 游戏页面导航与对局逻辑在步骤 4 接入
  }

  /// 清理离线玩家的座位并广播
  void _removeClient(int seat) {
    if (_closed) return;
    final session = _clients.remove(seat);
    if (session == null) return; // 已清理过（bye 与断线可能先后触发）
    session.close();
    _broadcast(
      NetMessage(
        type: NetMessageType.playerLeft,
        payload: {'seat': seat},
      ),
    );
    notifyListeners();
  }

  /// 向所有已入座客户端广播消息；[except] 指定的会话跳过
  void _broadcast(NetMessage message, {NetSession? except}) {
    for (final session in _clients.values) {
      if (identical(session, except)) continue;
      session.send(message);
    }
  }
}
