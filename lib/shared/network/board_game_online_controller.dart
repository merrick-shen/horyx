import 'package:horyx/shared/network/undo_resign_negotiation.dart';

/// 双人回合制棋类联机控制器的交互契约：棋类联机页共享层
/// （BoardGameOnlinePageMixin / BoardGameActionBar）所需的最小接口。
/// GomokuOnlineController / ChessOnlineController 已天然满足——均为
/// [OnlineGameControllerBase] 子类并混入 [UndoResignNegotiationMixin]，
/// 各自 implements 本接口即可，无需新增成员
abstract interface class BoardGameOnlineController {
  /// 对局终止信号（无胜负终止——断线/解散/对方离开——时非 null）
  String? get gameEndedText;

  /// 胜方文案（'黑方'/'红方'等，按棋局措辞）；对局进行中或异常终止为 null
  String? get winnerText;

  /// 悔棋协商状态（可写：悔棋弹窗期间对局终止时作废协商）
  UndoState get undoState;
  set undoState(UndoState value);

  /// 发起悔棋请求（悔自己的上一手，仅对方回合可发起）
  void requestUndo();

  /// 应答对方的悔棋请求
  void respondUndo(bool accept);

  /// 认输（判对方获胜）
  void resign();
}
