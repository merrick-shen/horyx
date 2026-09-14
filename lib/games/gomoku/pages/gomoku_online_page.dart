import 'package:flutter/material.dart';

import 'package:horyx/games/gomoku/services/gomoku_online_controller.dart';
import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/network/room_host.dart';
import 'package:horyx/shared/network/undo_resign_negotiation.dart';
import 'package:horyx/shared/utils/hint_bar.dart';
import 'package:horyx/shared/widgets/confirm_dialog.dart';
import 'package:horyx/shared/widgets/confirm_move_row.dart';
import 'package:horyx/shared/widgets/online_game_page_shell.dart';
import 'package:horyx/shared/widgets/page_content.dart';
import 'package:horyx/shared/widgets/primary_button.dart';
import 'package:horyx/shared/widgets/stone_board.dart';
import 'package:horyx/shared/widgets/stone_turn_card.dart';

/// 五子棋联机对局页
/// 由房间等待页满员开局后接管房间连接（房主/客户端所有权移入本页）。
/// 页面骨架（控制器生命周期/终局弹窗/退出确认/顶栏框架）见
/// [OnlineGamePageShell]，本页只实现五子棋的交互与视图：
/// 预选落子、悔棋协商弹窗、认输确认、胜负弹窗。
/// 视图结构与本地对局一致（执子卡 + 棋盘 + 操作按钮），联机适配点：
/// 仅轮到自己时可预选/确认落子，落子经房主校验后随广播全端生效。
/// 页面销毁即退出对局并关闭连接（联机对局不落本地存档）。
/// 再来一局暂未支持，终局后仅提供退出对局。
class GomokuOnlinePage extends StatefulWidget {
  const GomokuOnlinePage.host({
    super.key,
    required this.host,
    required this.boardSize,
  }) : client = null;

  const GomokuOnlinePage.client({super.key, required this.client})
    : host = null,
      boardSize = 0;

  /// 房主连接（房主模式；与本页生命周期绑定，dispose 时关闭即解散房间）
  final RoomHost? host;

  /// 客户端连接（客户端模式；dispose 时关闭即退出房间）
  final RoomClient? client;

  /// 建房所选棋盘规格（仅房主模式有效；客户端从开局载荷读取）
  final int boardSize;

  @override
  State<GomokuOnlinePage> createState() => _GomokuOnlinePageState();
}

class _GomokuOnlinePageState extends State<GomokuOnlinePage> {
  /// 预选落子位置；null 表示无预选（与本地对局一致的落子交互）
  (int, int)? _pending;

  /// 悔棋应答弹窗防重入（应答后复位，允许下次请求再弹）
  bool _undoDialogShown = false;

  /// 胜负弹窗只弹一次（无胜负终止弹窗由骨架处理，各用各的标志）
  bool _winDialogShown = false;

  /// 游戏事件钩子：悔棋请求弹窗；胜负终局弹胜利弹窗并标记终局
  /// （无胜负终止交回骨架通用弹窗）。
  /// 悔棋分支不再无条件短路终局判定：弹窗期间对局结束（如对方认输）
  /// 时关闭悔棋弹窗、复位协商状态并继续终局判定（B11）
  bool _onGameEvent(
    GomokuOnlineController controller,
    VoidCallback markEndShown,
  ) {
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

    // 胜负终局（五连/认输）；无胜负终止（断线/解散）优先走骨架通用弹窗
    if (_winDialogShown ||
        controller.gameEndedText != null ||
        controller.winnerText == null) {
      return false;
    }
    _winDialogShown = true;
    markEndShown();
    _showWinDialog(controller);
    return false;
  }

  /// 对方悔棋请求的应答弹窗：同意/拒绝后复位弹窗标志
  /// 同意则棋盘随广播回退，拒绝则对方收到提示
  Future<void> _showUndoRequestDialog(GomokuOnlineController controller) async {
    final result = await showConfirmDialog(
      context,
      title: '对方请求悔棋',
      message: '对方希望撤销上一手棋，是否同意？',
      confirmLabel: '同意',
      cancelLabel: '拒绝',
    );
    if (!mounted) return;
    setState(() => _undoDialogShown = false);
    controller.respondUndo(result == ConfirmResult.confirm);
  }

  /// 点击棋盘交叉点：仅轮到自己时可预选，终局或已占的点不可选
  void _onCellTap(GomokuOnlineController controller, int col, int row) {
    if (controller.winnerSeat != null) return;
    if (!controller.isMyTurn) return;
    if (controller.moves.contains((col, row))) return;
    setState(() => _pending = (col, row));
  }

  /// 取消预选：预选棋子消失
  void _cancelMove() {
    setState(() => _pending = null);
  }

  /// 确认落子：提交房主校验（房主模式即时生效，客户端随广播生效）
  /// 拒绝时经 onHint 提示原因，通过时清除预选等待同步
  void _confirmMove(GomokuOnlineController controller) {
    final selected = _pending;
    if (selected == null) return;
    if (controller.submitStone(selected.$1, selected.$2)) {
      setState(() => _pending = null);
    }
  }

  /// 胜利弹窗：区分五连获胜/认输；可留在棋盘查看棋型
  /// 中途退出不产生胜负（走骨架终局弹窗，无胜方），不进此弹窗
  Future<void> _showWinDialog(GomokuOnlineController controller) async {
    final winner = controller.winnerSeat == 1 ? '黑方' : '白方';
    final String message;
    if (controller.wonByResign) {
      message = controller.winnerSeat == controller.mySeat
          ? '对方认输了，你获得胜利'
          : '你认输了，本局告负';
    } else {
      message = '五子连珠，$winner赢得本局';
    }
    final result = await showConfirmDialog(
      context,
      title: '$winner胜利！',
      message: message,
      confirmLabel: '退出对局',
      cancelLabel: '查看棋盘',
    );
    if (!mounted) return;
    if (result == ConfirmResult.confirm) {
      _exitPage();
    }
  }

  /// 发起悔棋请求（按钮回调）：交控制器进入协商状态
  void _requestUndo(GomokuOnlineController controller) {
    if (controller.undoState != UndoState.idle) return;
    controller.requestUndo();
    setState(() {}); // 刷新按钮为「等待对方应答…」禁用态
  }

  /// 认输请求（按钮回调）：确认后判对方获胜
  Future<void> _requestResign(GomokuOnlineController controller) async {
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
  void _exitPage() {
    if (!mounted) return;
    exitPageClean(context);
  }

  @override
  Widget build(BuildContext context) {
    return OnlineGamePageShell<GomokuOnlineController>(
      title: '五子棋 · 联机',
      exitMessage: '退出后将断开与房间的连接，对局将结束',
      createController: () => widget.host != null
          ? GomokuOnlineController.host(
              widget.host!,
              boardSize: widget.boardSize,
            )
          : GomokuOnlineController.client(widget.client!),
      onGameEvent: _onGameEvent,
      buildGameView: (context, controller, requestExit) => _BoardView(
        boardSize: controller.boardSize,
        moves: controller.moves,
        pending: _pending,
        isMyTurn: controller.isMyTurn,
        winnerSeat: controller.winnerSeat,
        undoState: controller.undoState,
        hasMoves: controller.moves.isNotEmpty,
        onCellTap: (col, row) => _onCellTap(controller, col, row),
        onCancelMove: _cancelMove,
        onConfirmMove: () => _confirmMove(controller),
        onRequestUndo: () => _requestUndo(controller),
        onResign: () => _requestResign(controller),
        onExit: requestExit,
      ),
    );
  }
}

/// 联机对局视图：与本地对局同构（执子卡 + 棋盘 + 操作按钮）
/// 差异点：执子卡副标题提示等待对象；悔棋为协商制（发起请求、
/// 对方应答后随广播回退，等待应答期间按钮禁用防重复发起）；
/// 终局后按钮为「退出对局」（再来一局暂未支持）
class _BoardView extends StatelessWidget {
  const _BoardView({
    required this.boardSize,
    required this.moves,
    required this.pending,
    required this.isMyTurn,
    required this.winnerSeat,
    required this.undoState,
    required this.hasMoves,
    required this.onCellTap,
    required this.onCancelMove,
    required this.onConfirmMove,
    required this.onRequestUndo,
    required this.onResign,
    required this.onExit,
  });

  /// 棋盘路数（房主建房所选，随开局广播同步）
  final int boardSize;

  /// 已生效落子序列
  final List<(int, int)> moves;

  /// 预选落子位置；null 表示无预选
  final (int, int)? pending;

  /// 是否轮到自己落子（false 时棋盘不响应预选）
  final bool isMyTurn;

  /// 胜方座位号；null 表示对局进行中
  final int? winnerSeat;

  /// 悔棋协商状态（awaitingPeer 时悔棋按钮禁用防重复发起）
  final UndoState undoState;

  /// 是否已有落子（无子可悔时悔棋按钮禁用）
  final bool hasMoves;

  /// 点击棋盘交叉点回调
  final void Function(int col, int row) onCellTap;

  /// 点击「取消」回调：清除落子预选
  final VoidCallback onCancelMove;

  /// 点击「下棋」回调：确认落子
  final VoidCallback onConfirmMove;

  /// 点击「悔棋」回调：向对方发起悔棋请求
  final VoidCallback onRequestUndo;

  /// 点击「认输」回调：确认后判对方获胜
  final VoidCallback onResign;

  /// 终局后点击「退出对局」回调
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    // 落子确认按钮仅在棋盘上有预选棋子时出现
    final hasPending = pending != null;
    // 终局后无预选
    final isOver = winnerSeat != null;
    final blackTurn = moves.length.isEven;
    final winner = winnerSeat == null ? null : (winnerSeat == 1 ? '黑方' : '白方');

    return SizedBox.expand(
      child: PageContent(
        // 对局页收窄页边距：棋盘卡片自带边框，把宽度尽量让给棋盘
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 对局中提示执子方与等待对象；终局提示胜方（图标色对应棋子）
            StoneTurnCard(
              isOver: isOver,
              blackToMove: blackTurn,
              winner: winner,
              subtitle: isMyTurn ? '轮到你落子' : '等待对方落子',
            ),
            const SizedBox(height: 16),
            // 棋盘占据剩余空间，正方形自适应宽高较小者
            Expanded(
              child: Center(
                child: StoneBoard(
                  size: boardSize,
                  stones: [
                    for (int i = 0; i < moves.length; i++)
                      (moves[i].$1, moves[i].$2, i.isEven),
                  ],
                  pending: pending == null
                      ? null
                      : (pending!.$1, pending!.$2, moves.length.isEven),
                  onCellTap: onCellTap,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ConfirmMoveRow(
              visible: hasPending,
              onCancelMove: onCancelMove,
              onConfirmMove: onConfirmMove,
            ),
            const SizedBox(height: 12),
            if (isOver)
              // 终局：退出对局（再来一局暂未支持）
              PrimaryButton(
                label: '退出对局',
                icon: Icons.logout_rounded,
                onPressed: onExit,
              )
            else ...[
              // 悔棋：仅对方回合可发起（悔自己的上一手），
              // 等对方应答期间/无子可悔/轮到自己落子时禁用
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
          ],
        ),
      ),
    );
  }
}
