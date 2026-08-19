import 'dart:async';
import 'dart:io';

import '../../models/net_message.dart';
import 'net_protocol.dart';

/// TCP 会话：包装单条 Socket 连接的完整生命周期
/// 房主端（ServerSocket accept）与客户端（Socket connect）共用本封装，
/// 对上层提供统一的消息流、发送、心跳保活与断线回调
///
/// 心跳机制：每 [pingInterval] 发送一次 ping；连续 [heartbeatTimeout]
/// 未收到对端任何消息即判定掉线。无线场景的最大隐患是「半开连接」——
/// 对方锁屏/断网/杀应用后本端 TCP 不会立刻报错，看似还连着，
/// 心跳是唯一可靠的存活检测手段
class NetSession {
  NetSession._(this._socket, this._pingInterval, this._heartbeatTimeout);

  /// 以已建立的 Socket 构造会话并开始收消息与心跳
  /// [pingInterval] 与 [heartbeatTimeout] 支持注入以便测试缩短周期
  factory NetSession(
    Socket socket, {
    Duration pingInterval = const Duration(seconds: 5),
    Duration heartbeatTimeout = const Duration(seconds: 15),
  }) {
    final session = NetSession._(socket, pingInterval, heartbeatTimeout);
    session._start();
    return session;
  }

  final Socket _socket;
  final Duration _pingInterval;
  final Duration _heartbeatTimeout;

  /// 分帧解码器：缓冲半包字节、按 \n 切分粘包
  final NetFrameDecoder _decoder = NetFrameDecoder();

  /// 消息流控制器：广播式，房间页与对局页可先后/同时订阅
  final StreamController<NetMessage> _messageController =
      StreamController<NetMessage>.broadcast();

  /// 心跳定时器：周期性发送 ping 并检查对端活性
  Timer? _heartbeatTimer;

  /// 最近一次收到对端消息的时刻；心跳检查的基准
  DateTime _lastActiveAt = DateTime.now();

  /// 断线是否已触发：socket error 与 done 可能先后到达，保证清理与回调只执行一次
  bool _closed = false;

  /// 收到的消息流（已解码、心跳消息已被内部消化不出现在流中）
  /// 广播流：无订阅者时消息直接丢弃，订阅者需自行管理取消
  Stream<NetMessage> get messages => _messageController.stream;

  /// 断线回调：心跳超时、连接异常、对端关闭、本端主动 close 统一收敛于此，
  /// 上层（房间/对局页）只需处理这一个事件，无需区分断线原因
  VoidCallback? onDisconnected;

  /// 发送消息（NDJSON 编码后写入 socket）
  /// socket 已关闭时静默忽略：发送失败最终会由心跳/错误回调兜底
  void send(NetMessage message) {
    try {
      _socket.add(NetProtocol.encode(message));
    } catch (_) {
      // 写入失败（对端已断）不抛出，等待断线回调统一处理
    }
  }

  /// 主动关闭：先发送 bye 告知对端「主动离开」再销毁连接
  /// bye 发送失败无需处理——对端会按掉线处理，仅退出提示文案不同
  Future<void> close() => _handleDisconnect(sendBye: true);

  /// 启动消息监听与心跳定时
  void _start() {
    _socket.listen(
      (data) => _onData(data),
      onError: (_) => _handleDisconnect(),
      onDone: () => _handleDisconnect(),
      cancelOnError: true,
    );
    _heartbeatTimer = Timer.periodic(_pingInterval, (_) => _onHeartbeat());
  }

  /// 收到字节：先刷新活跃时刻（任何消息都证明对端存活，不必严格等 pong），
  /// 再经分帧解码分发到消息流；ping 由会话内部直接回 pong，
  /// 心跳细节对上层透明（房间/对局页无需关心 ping/pong）
  void _onData(List<int> data) {
    _lastActiveAt = DateTime.now();
    for (final message in _decoder.feed(data)) {
      if (message.type == NetMessageType.ping) {
        send(const NetMessage.pong());
        continue;
      }
      if (message.type == NetMessageType.pong) {
        continue; // 活跃时刻已刷新，pong 无需向上分发
      }
      _messageController.add(message);
    }
  }

  /// 心跳触发：发送 ping 探测；超时未收到对端任何消息则判定掉线断开
  void _onHeartbeat() {
    if (DateTime.now().difference(_lastActiveAt) > _heartbeatTimeout) {
      _handleDisconnect();
      return;
    }
    send(const NetMessage.ping());
  }

  /// 统一断线出口：清理资源、关闭消息流并回调上层（仅首次有效）
  Future<void> _handleDisconnect({bool sendBye = false}) async {
    if (_closed) return;
    _closed = true;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    if (sendBye) {
      send(const NetMessage.bye());
      // 给 bye 一点 flush 时间再销毁，尽量避免对端漏收
      try {
        await _socket.flush().timeout(_pingInterval);
      } catch (_) {
        // 对端已断导致 flush 失败属正常场景，忽略
      }
    }
    _socket.destroy();
    await _messageController.close();

    onDisconnected?.call();
  }
}

/// 无参回调的简洁别名（与 Flutter VoidCallback 语义一致，
/// 服务层不依赖 Flutter 体系故自行声明）
typedef VoidCallback = void Function();
