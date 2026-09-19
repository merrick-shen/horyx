import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:horyx/shared/network/net_message.dart';
import 'package:horyx/shared/network/net_session.dart';

/// 局域网房间 - 房主端服务
/// 职责：TCP 监听（端口占用自动顺延）、hello 握手与座位分配、
/// 座位列表维护、玩家加入/离开广播、满员自动广播开局。
/// 房主自己是玩家 1（本机，无网络会话），客户端依次占用玩家 2..N。
/// 对局消息（单词校验与广播）由步骤 4 的游戏层接入，本类只管房间生命周期。
class RoomHost extends ChangeNotifier {
  RoomHost({
    required this.gameName,
    required this.capacity,
    this.basePort = defaultPort,
    this.gameStartPayload = const {},
  }) : assert(capacity >= 2, '房间至少 2 人');

  /// 游戏名称（等待页标识卡展示用，随 joinResponse 发给客户端，如「单词PK」）
  final String gameName;

  /// 本局总人数（2-8，含房主）
  final int capacity;

  /// 满员开局消息的附加载荷（游戏专属数据，随 gameStart 广播给全员）
  /// 如五子棋的棋盘规格；单词PK等无附加数据的游戏保持空
  final Map<String, dynamic> gameStartPayload;

  /// 监听起始端口：绑定失败自动尝试 +1（最多 10 个候选）；
  /// 测试可传 0 让系统分配临时端口，避免与真实端口冲突
  final int basePort;

  /// 默认 TCP 监听端口（避开常见服务端口，减少被占用概率）
  static const int defaultPort = 45654;

  ServerSocket? _server;

  /// 是否已释放（[dispose] 后置位）：迟到的房间事件不再 notifyListeners，
  /// 防止对已 dispose 的通知器触发 debug 断言
  bool _disposed = false;

  /// dispose 后安全的监听通知（释放后的迟到事件静默丢弃）
  void _notifyChanged() {
    if (!_disposed) notifyListeners();
  }

  /// 已入座的客户端：座位号 -> 会话（座位 1 为房主本机，不在此表）
  final Map<int, NetSession> _clients = {};

  /// 已接受但尚未握手入座的会话（10 秒握手超时窗内的连接）：
  /// 房主解散时需一并关闭——否则这些 socket 与握手 Timer 最长滞留 10 秒，
  /// 且其中在途的 hello 会在解散后到达，若无守卫将"幽灵入座"（见 _handleHello）
  final List<NetSession> _handshaking = [];

  /// 实际监听端口（start 成功后有效；basePort 为 0 时是系统分配值）
  int _port = 0;
  int get port => _port;

  /// 是否已满员并广播过开局
  bool _gameStarted = false;
  bool get gameStarted => _gameStarted;

  /// 房间是否已关闭（房主主动解散）
  bool _closed = false;
  bool get closed => _closed;

  /// 对局消息回调（游戏层挂接）：已入座客户端发来的非房间管理类消息
  /// （如 wordSubmit）按座位转发；开局前为 null，消息被忽略
  void Function(int seat, NetMessage message)? onGameMessage;

  /// 玩家离开回调（游戏层挂接）：对局中有人掉线/退出时由游戏层
  /// 处理回合跳过与全员离开判定；等待阶段（未开局）无消费者
  void Function(int seat)? onSeatLeft;

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
        _notifyChanged();
        return true;
      } on SocketException {
        // 端口被占用，尝试下一个
        continue;
      }
    }
    return false;
  }

  /// 解散房间：断开所有已入座玩家与握手中途的连接（各自发送 bye），停止监听
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // 未握手连接不在 _clients 中，需单独关闭（bye 后其断线回调负责
    // 从握手名单移除；名单先快照清空，避免回调期间边遍历边修改）
    final handshaking = List.of(_handshaking);
    _handshaking.clear();
    final sessions = [..._clients.values, ...handshaking];
    _clients.clear();
    // 先发 bye 再关 socket；会话断开回调因 _closed 已置位而不再触发座位清理。
    // 并行关闭：半开连接（对端不回包）下单会话 flush 会挂满超时（默认 5 秒），
    // 串行等待随人数线性叠加（8 人房间最坏约 40 秒），并行后只等最慢的一个
    await Future.wait(sessions.map((session) => session.close()));
    await _server?.close();
    _server = null;
    _notifyChanged();
  }

  /// 新连接接入：建立会话并等待 hello 握手，10 秒未握手则断开
  /// （防止空连接长期占用资源）
  void _onAccept(Socket socket) {
    if (_closed) {
      socket.destroy();
      return;
    }
    final session = NetSession(socket);
    _handshaking.add(session);
    var seat = 0; // 0 表示尚未握手入座
    Timer? helloTimeout = Timer(const Duration(seconds: 10), () {
      if (seat == 0) session.close();
    });

    session.onDisconnected = () {
      _handshaking.remove(session);
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
          // 入座后移交 _clients 管理；被拒（返回 0）的会话已随拒绝路径
          // close，断线回调会将其从握手名单移除
          if (seat != 0) _handshaking.remove(session);
        case NetMessageType.bye:
          // 客户端主动退出：bye 后 socket 关闭会触发 onDisconnected 统一清理
          break;
        default:
          // 对局消息按座位转发游戏层（开局前未挂接，忽略）
          if (seat != 0) onGameMessage?.call(seat, message);
          break;
      }
    });
  }

  /// 处理握手：解散后迟到的 hello 直接断开（防幽灵入座）；开局后或满员
  /// 则拒绝并断开；否则分配最小空位、应答加入结果、广播入座消息，
  /// 返回分配的座位号（拒绝时返回 0）
  int _handleHello(NetSession session) {
    // 房主已解散：解散瞬间仍在途的 hello 若放行入座，客户端会收到
    // ok:true 的 joinResponse 进入等待页——此后双方心跳互保活，
    // 房主不会再有第二次 close()（入口短路），客户端永久卡在等待页。
    // 此处断开让客户端按掉线/解散收场（等待页转为断开提示视图）
    if (_closed) {
      session.close();
      return 0;
    }
    // 开局后不再放人：中途退出的座位虽空出，但对局进行中新加入者
    // 无法追上已同步的对局状态（重连/补位为后续增强）
    if (_gameStarted) {
      session.send(
        const NetMessage(
          type: NetMessageType.joinResponse,
          payload: {'ok': false, 'reason': 'gameStarted'},
        ),
      );
      session.close();
      return 0;
    }
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

    // 应答：游戏名 + 自己的座位 + 房间总人数 + 当前所有已入座玩家（供等待页渲染）
    // 客户端改为输入 IP 加入后，连接前不知道游戏名，依赖此处的 gameName
    session.send(
      NetMessage(
        type: NetMessageType.joinResponse,
        payload: {
          'ok': true,
          'gameName': gameName,
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
    _notifyChanged();

    // 满员自动开局（重开场景由步骤 4 控制，此处只广播一次）
    if (isFull && !_gameStarted) _startGame();
    return seat;
  }

  /// 满员开局：广播 gameStart（含游戏专属载荷），客户端进入「即将开始」状态
  void _startGame() {
    _gameStarted = true;
    _broadcast(
      NetMessage(
        type: NetMessageType.gameStart,
        payload: {'playerCount': capacity, ...gameStartPayload},
      ),
    );
    _notifyChanged();
    // 游戏页面导航与对局逻辑由各游戏的联机层接入
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
    // 对局中的离开交由游戏层（回合跳过/全员离开判定）；等待阶段无消费者
    onSeatLeft?.call(seat);
    _notifyChanged();
  }

  /// 对局广播：向所有已入座客户端发送消息（游戏层使用）
  void broadcast(NetMessage message) => _broadcast(message);

  /// 定向发送：向指定座位的客户端发送消息（游戏层使用）
  void sendTo(int seat, NetMessage message) => _clients[seat]?.send(message);

  /// 向所有已入座客户端广播消息；[except] 指定的会话跳过
  void _broadcast(NetMessage message, {NetSession? except}) {
    for (final session in _clients.values) {
      if (identical(session, except)) continue;
      session.send(message);
    }
  }

  /// 释放通知器并解散房间（所有权终点的统一出口）：
  /// 先切断游戏层回调再关房，关闭窗口期的客户端消息不再进入本对象；
  /// close 的 bye flush 可能耗时数秒，dispose 按约定同步返回、连接后台关闭。
  /// dispose 后迟到的断线清理不会通知监听者
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    onGameMessage = null;
    onSeatLeft = null;
    close();
    super.dispose();
  }
}
