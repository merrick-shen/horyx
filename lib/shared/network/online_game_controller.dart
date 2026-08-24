import 'package:flutter/foundation.dart';

import 'package:horyx/shared/network/net_message.dart';
import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/network/room_host.dart';

/// 联机对局控制器公共基类（房主权威模型）
/// 统一各联机游戏的公共骨架：持有 host/client 连接、挂接房间回调、
/// 断线终局处理、dispose 关闭连接、提交回执构造与拒绝文案映射。
/// 游戏差异下沉为子类职责：
/// - [onHostGameMessage] / [onClientGameMessage]：对局消息处理
/// - [onSeatLeft]：玩家离开语义（多人局跳过回合 / 2 人局直接终局）
/// - [resultMessageType]：提交回执的消息类型（stoneResult / wordResult）
/// - [reasonText]：拒绝原因 -> 用户可读文案
/// 约定：页面销毁（dispose）即退出对局，连接关闭由本基类统一负责
abstract class OnlineGameControllerBase extends ChangeNotifier {
  OnlineGameControllerBase({
    required this.host,
    required this.client,
    required this.mySeat,
  });

  /// 房主连接（仅房主模式非空；子类发送/广播、页面判空用）
  @protected
  final RoomHost? host;

  /// 客户端连接（仅客户端模式非空；子类上报消息用）
  @protected
  final RoomClient? client;

  /// 我的座位号（房主固定 1 号位；客户端为实际分配座位）
  final int mySeat;

  /// 校验拒绝等提示回调（页面接 SnackBar 展示；拒绝理由来自房主）
  void Function(String message)? onHint;

  /// 对局终止说明（对方离开/房主解散/连接断开等无胜负的终止）；
  /// 胜负结果不走此字段（各游戏自行建模，如五子棋的 winnerSeat）。
  /// 非 null 时页面弹窗告知并结束，之后不再恢复
  String? gameEndedText;

  /// 提交回执的消息类型（子类提供：stoneResult / wordResult）
  @protected
  NetMessageType get resultMessageType;

  /// 房主模式挂接：对局消息与玩家离开回调（子类构造体末尾调用）
  @protected
  void attachHost() {
    host?.onGameMessage = onHostGameMessage;
    host?.onSeatLeft = onSeatLeft;
  }

  /// 客户端模式挂接：对局消息（含暂存回放）与连接状态（子类构造体末尾调用）
  ///
  /// 必须在子类字段全部初始化完成后调用：attachGameHandler 会同步回放
  /// 暂存消息，过早挂接会在子类 late 字段未就绪时触发消息处理
  @protected
  void attachClient() {
    client?.attachGameHandler(onClientGameMessage);
    client?.addListener(_onClientChanged);
  }

  /// 房主侧：已入座客户端发来的对局消息（子类实现游戏逻辑）
  @protected
  void onHostGameMessage(int seat, NetMessage message);

  /// 客户端侧：房主发来的对局消息（子类实现游戏逻辑）
  @protected
  void onClientGameMessage(NetMessage message);

  /// 房主侧：玩家中途离开（掉线/主动退出），子类实现回合跳过/终局判定
  @protected
  void onSeatLeft(int seat);

  /// 房主拒绝原因 -> 用户可读文案（子类按游戏文案映射）
  @protected
  String reasonText(Object? reason);

  /// 客户端侧：连接状态变化（断线/房主解散 -> 对局终止）
  void _onClientChanged() {
    if (client?.phase == RoomClientPhase.disconnected &&
        gameEndedText == null) {
      gameEndedText = client!.disconnectText;
      notifyListeners();
    }
  }

  /// 构造提交结果回执（仅发给提交者；拒绝时携带原因，null-aware 自动省略）
  @protected
  NetMessage resultMessage(bool ok, String? reason) => NetMessage(
        type: resultMessageType,
        payload: {'ok': ok, 'reason': ?reason},
      );

  @override
  void dispose() {
    // 页面销毁即退出对局：关闭底层房间连接
    // （房主解散会通知全员；客户端退出由各游戏的房主侧 onSeatLeft 处理）
    client?.removeListener(_onClientChanged);
    host?.close();
    client?.close();
    super.dispose();
  }
}
