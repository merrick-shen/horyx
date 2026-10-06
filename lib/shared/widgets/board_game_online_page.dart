import 'package:flutter/material.dart';

import 'package:horyx/shared/network/board_game_online_controller.dart';
import 'package:horyx/shared/network/undo_resign_negotiation.dart';
import 'package:horyx/shared/utils/page_exit.dart';
import 'package:horyx/shared/widgets/confirm_dialog.dart';
import 'package:horyx/shared/widgets/primary_button.dart';

/// 双人回合制棋类联机页共享层（gomoku / chess 联机对局页复用）：
/// 游戏事件三段式处理（悔棋请求弹窗 → 终局关弹窗 → 胜负弹窗）、
/// 悔棋/认输按钮回调与底部操作按钮组件。两页面只保留各自棋盘视图
/// 与胜负文案——同一状态机此前在两页逐行复制，改协商规则（如限时/
/// 限次）必然双侧静默分叉，现收敛于此唯一定义

/// 棋类联机对局页能力混入（页面 State 混入使用）：
/// 游戏事件三段式处理与悔棋/认输按钮回调、退出收尾。
/// 混入方需提供 [undoRequestMessage] 文案措辞；胜负弹窗的棋局专属文案
/// 经 [handleGameEvent] 的 showWinDialog 钩子由页面自行组装
/// （共用弹窗外观见 [showBoardGameWinDialog]）
mixin BoardGameOnlinePageMixin<W extends StatefulWidget> on State<W> {
  /// 悔棋应答弹窗防重入（应答后复位，允许下次请求再弹）
  bool _undoDialogShown = false;

  /// 胜负弹窗只弹一次（无胜负终止弹窗由骨架处理，各用各的标志）
  bool _winDialogShown = false;

  /// 对方请求悔棋的弹窗说明文案（撤销"上一手棋"/"上一步走子"按棋局措辞）
  String get undoRequestMessage;

  /// 游戏事件钩子：悔棋请求弹窗；胜负终局弹胜利弹窗并标记终局
  /// （无胜负终止交回骨架通用弹窗）。
  /// 悔棋分支不再无条件短路终局判定：弹窗期间对局结束（如对方认输）
  /// 时关闭悔棋弹窗、复位协商状态并继续终局判定（B11）
  bool handleGameEvent(
    BoardGameOnlineController controller, {
    required VoidCallback markEndShown,
    required Future<void> Function() showWinDialog,
  }) {
    final ended =
        controller.gameEndedText != null || controller.winnerText != null;

    // 悔棋请求弹窗（未终局且非自己已发起状态）
    if (!ended &&
        controller.undoState == UndoState.peerRequesting &&
        !_undoDialogShown) {
      _undoDialogShown = true;
      _showUndoRequestDialog(controller);
      return true;
    }

    // 悔棋弹窗未应答时对局结束：关弹窗、协商作废（对局已终止，
    // 无需应答对方），继续终局判定；pop 关闭的是栈顶的悔棋弹窗，
    // 其 await 恢复后 respondUndo 因协商已复位而 no-op
    if (ended && _undoDialogShown) {
      _undoDialogShown = false;
      controller.undoState = UndoState.idle;
      Navigator.of(context).pop();
    }

    // 胜负终局；无胜负终止（断线/解散）优先走骨架通用弹窗
    if (_winDialogShown ||
        controller.gameEndedText != null ||
        controller.winnerText == null) {
      return false;
    }
    _winDialogShown = true;
    markEndShown();
    showWinDialog();
    return false;
  }

  /// 对方悔棋请求的应答弹窗：同意/拒绝后复位弹窗标志
  /// 同意则棋盘随广播回退，拒绝则对方收到提示
  Future<void> _showUndoRequestDialog(
    BoardGameOnlineController controller,
  ) async {
    final result = await showConfirmDialog(
      context,
      title: '对方请求悔棋',
      message: undoRequestMessage,
      confirmLabel: '同意',
      cancelLabel: '拒绝',
    );
    if (!mounted) return;
    setState(() => _undoDialogShown = false);
    controller.respondUndo(result == ConfirmResult.confirm);
  }

  /// 发起悔棋请求（按钮回调）：交控制器进入协商状态
  void requestUndoFor(BoardGameOnlineController controller) {
    if (controller.undoState != UndoState.idle) return;
    controller.requestUndo();
    setState(() {}); // 刷新按钮为「等待对方应答…」禁用态
  }

  /// 认输请求（按钮回调）：确认后判对方获胜
  Future<void> requestResignFor(BoardGameOnlineController controller) async {
    final result = await showConfirmDialog(
      context,
      title: '认输？',
      message: '认输后本局将判定对方获胜',
      confirmLabel: '认输',
    );
    if (!mounted) return;
    if (result == ConfirmResult.confirm) {
      controller.resign();
    }
  }

  /// 退出页面：先移除未关闭的错误提示再返回
  void exitBoardGamePage() {
    if (!mounted) return;
    exitPageClean(context);
  }
}

/// 胜负终局弹窗（棋类通用外观）：确认「退出对局」离开，取消「查看棋盘」
/// 留守。胜利文案由各棋局组装（在
/// [BoardGameOnlinePageMixin.handleGameEvent] 的 showWinDialog 钩子内调用）
Future<void> showBoardGameWinDialog(
  BuildContext context, {
  required String winner,
  required String message,
  required VoidCallback onExit,
}) async {
  final result = await showConfirmDialog(
    context,
    title: '$winner胜利！',
    message: message,
    confirmLabel: '退出对局',
    cancelLabel: '查看棋盘',
  );
  if (result == ConfirmResult.confirm) {
    onExit();
  }
}

/// 棋类联机对局底部操作按钮（退出/悔棋/认输，两棋类共用）。
/// [showExit] 为 true 时整组替换为「退出对局」单按钮：终局（含无胜负
/// 终止）后悔棋/认输均已无意义——五子棋原先在无胜负终止后仍显示
/// 失效的悔棋/认输按钮，现与象棋统一
class BoardGameActionBar extends StatelessWidget {
  const BoardGameActionBar({
    super.key,
    required this.showExit,
    required this.undoState,
    required this.hasMoves,
    required this.isMyTurn,
    required this.onRequestUndo,
    required this.onResign,
    required this.onExit,
  });

  /// 对局是否已结束（胜负已定或异常终止）：true 时仅显示「退出对局」
  final bool showExit;

  /// 悔棋协商状态（awaitingPeer 时按钮进入「等待对方应答…」禁用态）
  final UndoState undoState;

  /// 是否已有手数（无子可悔时悔棋按钮禁用）
  final bool hasMoves;

  /// 是否轮到自己（悔棋仅对方回合可发起：悔自己的上一手）
  final bool isMyTurn;

  /// 点击「悔棋」回调：向对方发起悔棋请求
  final VoidCallback onRequestUndo;

  /// 点击「认输」回调：确认后判对方获胜
  final VoidCallback onResign;

  /// 终局后点击「退出对局」回调
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    if (showExit) {
      // 终局：退出对局（再来一局暂未支持）
      return PrimaryButton(
        label: '退出对局',
        icon: Icons.logout_rounded,
        onPressed: onExit,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 悔棋：仅对方回合可发起（悔自己的上一手），
        // 等对方应答期间/无子可悔/轮到自己时禁用
        PrimaryButton(
          label: undoState == UndoState.awaitingPeer ? '等待对方应答…' : '悔棋',
          icon: Icons.undo_rounded,
          onPressed: undoState == UndoState.idle && hasMoves && !isMyTurn
              ? onRequestUndo
              : null,
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          label: '认输',
          icon: Icons.flag_rounded,
          onPressed: onResign,
        ),
      ],
    );
  }
}
