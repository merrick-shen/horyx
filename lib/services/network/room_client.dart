import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/net_message.dart';
import 'net_session.dart';

/// 客户端加入房间的阶段
enum RoomClientPhase {
  /// 连接中（含等待房主应答加入结果）
  connecting,

  /// 已加入，等待其他玩家入座
  joined,

  /// 满员，即将开局
  gameStarting,

  /// 加入失败（地址不可达 / 房间已满 / 应答超时）
  failed,

  /// 加入成功后与房间断开（房主解散或网络中断）
  disconnected,
}

/// 局域网房间 - 客户端服务
/// 职责：连接房主、hello 握手、等待加入结果、维护座位快照（入座/离开/开局）。
/// 对局消息（wordSubmit/wordApplied 等）由步骤 4 的游戏层接入。
class RoomClient extends ChangeNotifier {
  RoomClient({required this.host, required this.port});

  /// 房主地址（IP 或主机名）
  final String host;

  /// 房主监听端口
  final int port;

  NetSession? _session;
  Timer? _joinTimeout;

  /// 当前阶段
  RoomClientPhase phase = RoomClientPhase.connecting;

  /// 加入失败原因（phase 为 failed 时有效，面向用户可直接展示）
  String failReason = '';

  /// 收到过房主的 bye（用于区分「房主解散」与「异常掉线」）
  bool _byeReceived = false;

  /// 对局消息处理器（游戏层挂接）：房主发来的对局消息（wordResult/wordApplied 等）
  /// 未挂接期间的消息暂存于 [_pendingGameMessages]，挂接后按序回放——
  /// 覆盖「收到 gameStart 到对局页挂接完成」的间隙，避免漏消息导致状态分叉
  void Function(NetMessage message)? onGameMessage;

  /// 待回放的对局消息（上限防御：异常情况下不至于无限增长）
  final List<NetMessage> _pendingGameMessages = [];

  /// 挂接对局消息处理器并回放暂存消息（游戏层调用一次）
  void attachGameHandler(void Function(NetMessage message) handler) {
    onGameMessage = handler;
    final pending = List.of(_pendingGameMessages);
    _pendingGameMessages.clear();
    for (final message in pending) {
      handler(message);
    }
  }

  /// 发送对局消息给房主（wordSubmit 等，游戏层使用）
  void send(NetMessage message) => _session?.send(message);

  /// 断开时展示给用户的提示文案
  String get disconnectText =>
      _byeReceived ? '房主已解散房间' : '与房间的连接已断开，请检查网络';

  /// 自己的座位号（加入成功后有效；房主固定 1 号位）
  int? mySeat;

  /// 房间总人数
  int capacity = 0;

  /// 满员开局载荷（游戏专属数据，如五子棋的棋盘规格）
  /// 由房主建房时提供、随 gameStart 广播；游戏层开局时读取
  Map<String, dynamic> startPayload = const {};

  /// 座位快照（含房主 1 号位）；用 Set 去重，展示时排序
  final Set<int> _seats = {};
  List<int> get seats => _seats.toList()..sort();

  /// 发起连接：TCP 连接 -> 发送 hello -> 等待 joinResponse（8 秒超时）
  /// 结果通过 [phase] 与 [failReason] 通知，调用方监听本对象即可
  Future<void> connect() async {
    try {
      final socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 5));
      final session = NetSession(socket);
      _session = session;
      session.onDisconnected = _onDisconnected;
      session.messages.listen(_onMessage);
      session.send(const NetMessage(type: NetMessageType.hello));
      // 房主应答超时：版本不兼容的客户端消息会被房主静默丢弃（解析失败），
      // 同样走到这里，文案需兼顾提示
      _joinTimeout = Timer(const Duration(seconds: 8), () {
        _fail('连接超时，请检查房间地址；若地址无误，可能是双方 App 版本不一致');
      });
    } catch (_) {
      _fail('无法连接到房间，请确认地址无误且双方连接同一 Wi-Fi');
    }
  }

  /// 处理房主消息，维护座位快照与阶段
  void _onMessage(NetMessage message) {
    switch (message.type) {
      case NetMessageType.joinResponse:
        _joinTimeout?.cancel();
        _joinTimeout = null;
        final ok = message.payload['ok'] == true;
        if (!ok) {
          _fail(_reasonText(message.payload['reason']));
          return;
        }
        mySeat = message.payload['seat'] as int?;
        capacity = (message.payload['capacity'] as int?) ?? 0;
        final players = message.payload['players'];
        if (players is List) {
          _seats.addAll(players.whereType<int>());
        }
        // 房主广播 playerJoined 时会跳过新加入者本人，
        // 自己的座位需在此主动补入，否则等待页会把自己显示成空位
        if (mySeat != null) _seats.add(mySeat!);
        phase = RoomClientPhase.joined;
        notifyListeners();
      case NetMessageType.playerJoined:
        _seats.add(message.payload['seat'] as int? ?? -1);
        notifyListeners();
      case NetMessageType.playerLeft:
        _seats.remove(message.payload['seat'] as int? ?? -1);
        notifyListeners();
      case NetMessageType.gameStart:
        // 开局载荷整体保存，游戏层按需取用（如五子棋的 boardSize）
        startPayload = Map<String, dynamic>.of(message.payload);
        phase = RoomClientPhase.gameStarting;
        notifyListeners();
      case NetMessageType.bye:
        _byeReceived = true;
      default:
        // 对局消息转发游戏层；未挂接（开局跳转间隙）时暂存待回放
        if (onGameMessage != null) {
          onGameMessage!(message);
        } else if (_pendingGameMessages.length < 100) {
          _pendingGameMessages.add(message);
        }
        break;
    }
  }

  /// 连接断开（含主动关闭）：仅在已加入阶段才提示断开，
  /// 失败阶段的关闭是自身清理动作，不覆盖失败状态
  void _onDisconnected() {
    _joinTimeout?.cancel();
    _joinTimeout = null;
    if (phase == RoomClientPhase.failed) return;
    phase = RoomClientPhase.disconnected;
    notifyListeners();
  }

  /// 标记失败并清理连接
  void _fail(String reason) {
    _joinTimeout?.cancel();
    _joinTimeout = null;
    failReason = reason;
    phase = RoomClientPhase.failed;
    final session = _session;
    _session = null;
    // 先置阶段再关连接：断开回调看到 failed 后不再改写状态
    session?.close();
    notifyListeners();
  }

  /// 拒绝原因 -> 用户可读文案
  String _reasonText(Object? reason) {
    switch (reason) {
      case 'roomFull':
        return '房间已满，无法加入';
      case 'gameStarted':
        return '对局已开始，无法加入';
      default:
        return '加入失败，请稍后重试';
    }
  }

  /// 主动退出房间（发送 bye 后关闭连接）
  Future<void> close() async {
    _joinTimeout?.cancel();
    _joinTimeout = null;
    final session = _session;
    _session = null;
    await session?.close();
  }
}
