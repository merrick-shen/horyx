import 'package:flutter/material.dart';

import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/models/chess_piece.dart';
import 'package:horyx/games/chess/services/chess_online_controller.dart';
import 'package:horyx/games/chess/services/chess_rules.dart';
import 'package:horyx/games/chess/widgets/chess_board_canvas.dart';
import 'package:horyx/games/chess/widgets/chess_check_flash.dart';
import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/network/room_host.dart';
import 'package:horyx/shared/utils/hint_bar.dart';
import 'package:horyx/shared/widgets/confirm_dialog.dart';
import 'package:horyx/shared/widgets/confirm_move_row.dart';
import 'package:horyx/shared/widgets/online_game_page_shell.dart';
import 'package:horyx/shared/widgets/page_content.dart';
import 'package:horyx/shared/widgets/primary_button.dart';
import 'package:horyx/shared/widgets/turn_card.dart';

/// 中国象棋联机对局页
/// 由房间等待页满员开局后接管房间连接（房主/客户端所有权移入本页）。
/// 页面骨架（控制器生命周期/终局弹窗/退出确认/顶栏框架）见
/// [OnlineGamePageShell]，本页只实现象棋的交互与视图：
/// 选子预选走法、悔棋协商弹窗、认输确认、胜负弹窗、将军提示。
/// 视图结构与本地对局一致（行棋提示卡 + 棋盘 + 操作按钮），联机适配点：
/// 仅轮到自己时可预选/确认走子，走子经房主校验后随广播全端生效。
/// 页面销毁即退出对局并关闭连接（联机对局不落本地存档）。
/// 再来一局暂未支持，终局后仅提供退出对局。
class ChessOnlinePage extends StatefulWidget {
  const ChessOnlinePage.host({super.key, required this.host})
    : client = null;

  const ChessOnlinePage.client({super.key, required this.client})
    : host = null;

  /// 房主连接（房主模式；与本页生命周期绑定，dispose 时关闭即解散房间）
  final RoomHost? host;

  /// 客户端连接（客户端模式；dispose 时关闭即退出房间）
  final RoomClient? client;

  @override
  State<ChessOnlinePage> createState() => _ChessOnlinePageState();
}

class _ChessOnlinePageState extends State<ChessOnlinePage> {
  /// 当前选中的己方棋子；null 表示无选中（与本地对局一致的走子交互）
  ChessPos? _selected;

  /// 选中棋子的合法走法缓存
  List<ChessMove> _legalMoves = const [];

  /// 待确认走法（ConfirmMoveRow 显示中）；null 表示无预选
  ChessMove? _pendingMove;

  /// 「将军」闪烁提示触发计数：检测到新走子后对方被将军时递增
  int _checkFlashTrigger = 0;

  /// 上一次通知时的走子数（识别新增走子，避免重复触发将军提示）
  int _lastMoveCount = 0;

  /// 悔棋应答弹窗防重入（应答后复位，允许下次请求再弹）
  bool _undoDialogShown = false;

  /// 胜负弹窗只弹一次（无胜负终止弹窗由骨架处理，各用各的标志）
  bool _winDialogShown = false;

  /// 游戏事件钩子：悔棋请求弹窗；胜负终局弹胜利弹窗并标记终局
  /// （无胜负终止交回骨架通用弹窗）。
  /// 悔棋分支不再无条件短路终局判定：弹窗期间对局结束（如对方认输）
  /// 时关闭悔棋弹窗、复位协商状态并继续终局判定（B11）
  bool _onGameEvent(
    ChessOnlineController controller,
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

    // 胜负终局（将死/困毙/认输）；无胜负终止（断线/解散）优先走骨架通用弹窗
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
  Future<void> _showUndoRequestDialog(ChessOnlineController controller) async {
    final result = await showConfirmDialog(
      context,
      title: '对方请求悔棋',
      message: '对方希望撤销上一步走子，是否同意？',
      confirmLabel: '同意',
      cancelLabel: '拒绝',
    );
    if (!mounted) return;
    setState(() => _undoDialogShown = false);
    controller.respondUndo(result == ConfirmResult.confirm);
  }

  /// 点击棋盘格：仅轮到自己时可预选（选己方棋子/选中后点合法落点）
  void _onCellTap(ChessOnlineController controller, ChessPos pos) {
    if (controller.winnerSeat != null) return;
    if (!controller.isMyTurn) return;
    if (controller.board.pieceAt(pos) != null &&
        controller.board.pieceAt(pos)!.color == controller.myColor) {
      // 选/换己方棋子：重算合法走法缓存
      setState(() {
        _selected = pos;
        _legalMoves = ChessRules.legalMovesFor(controller.board, pos);
        _pendingMove = null;
      });
      return;
    }
    // 已有选中且点击合法落点：进入待确认
    if (_selected != null) {
      for (final move in _legalMoves) {
        if (move.to == pos) {
          setState(() => _pendingMove = move);
          return;
        }
      }
      // 非法落点/其他位置：清除选中
      setState(() {
        _selected = null;
        _legalMoves = const [];
        _pendingMove = null;
      });
    }
  }

  /// 取消待确认走法（保留选中状态，可另选落点）
  void _cancelMove() {
    setState(() => _pendingMove = null);
  }

  /// 确认走子：提交房主校验（房主模式即时生效，客户端随广播生效）
  /// 拒绝时经 onHint 提示原因，通过时清除选中等待同步
  void _confirmMove(ChessOnlineController controller) {
    final move = _pendingMove;
    if (move == null) return;
    if (controller.submitMove(move)) {
      setState(() {
        _selected = null;
        _legalMoves = const [];
        _pendingMove = null;
      });
    }
  }

  /// 胜利弹窗：按终局原因区分将死/困毙/认输（认输区分视角）；
  /// 可留在棋盘查看棋型。中途退出不产生胜负（走骨架终局弹窗），不进此弹窗
  Future<void> _showWinDialog(ChessOnlineController controller) async {
    final winner = controller.winnerText!;
    final String message;
    switch (controller.winReason) {
      case ChessEndReason.resign:
        message = controller.winnerSeat == controller.mySeat
            ? '对方认输了，你获得胜利'
            : '你认输了，本局告负';
      case ChessEndReason.stalemate:
        message = '对方无子可动（困毙），$winner获胜';
      case ChessEndReason.checkmate || null:
        message = '将死对方，$winner赢得本局';
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
  void _requestUndo(ChessOnlineController controller) {
    if (controller.undoState != UndoState.idle) return;
    controller.requestUndo();
    setState(() {}); // 刷新按钮为「等待对方应答…」禁用态
  }

  /// 认输请求（按钮回调）：确认后判对方获胜
  Future<void> _requestResign(ChessOnlineController controller) async {
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

  /// 控制器通知回调（经骨架 onControllerChanged 在 build 路径外调用）：
  /// 检测走子数变化——新增走子时按当前行棋方判定一次将军并递增闪屏
  /// 触发器；悔棋回退（走子数减少）时清除本方选中与预选——对方棋子
  /// 归位后走法集已变化，残留的高亮与待确认走法基于回退前局面，属于
  /// 过期状态。回退路径不递增闪屏触发器：回退是协商结果而非新走子，
  /// 回退后恰好将军不应播放「将军」提示
  void _onControllerChanged(ChessOnlineController controller) {
    if (controller.moves.length == _lastMoveCount) return;
    final reverted = controller.moves.length < _lastMoveCount;
    _lastMoveCount = controller.moves.length;
    if (reverted) {
      _selected = null;
      _legalMoves = const [];
      _pendingMove = null;
      return;
    }
    if (ChessRules.isInCheck(controller.board, controller.turnColor)) {
      _checkFlashTrigger++;
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnlineGamePageShell<ChessOnlineController>(
      title: '中国象棋 · 联机',
      exitMessage: '退出后将断开与房间的连接，对局将结束',
      createController: () => widget.host != null
          ? ChessOnlineController.host(widget.host!)
          : ChessOnlineController.client(widget.client!),
      onControllerChanged: _onControllerChanged,
      onGameEvent: _onGameEvent,
      buildGameView: (context, controller, requestExit) {
        return _BoardView(
          controller: controller,
          selected: _selected,
          legalTargets: {for (final m in _legalMoves) m.to},
          pendingMove: _pendingMove,
          checkFlashTrigger: _checkFlashTrigger,
          onCellTap: (pos) => _onCellTap(controller, pos),
          onCancelMove: _cancelMove,
          onConfirmMove: () => _confirmMove(controller),
          onRequestUndo: () => _requestUndo(controller),
          onResign: () => _requestResign(controller),
          onExit: requestExit,
        );
      },
    );
  }
}

/// 联机对局视图：与本地对局同构（行棋提示卡 + 棋盘 + 操作按钮）
/// 差异点：提示卡副标题提示等待对象；悔棋为协商制（发起请求、
/// 对方应答后随广播回退，等待应答期间按钮禁用防重复发起）；
/// 终局后按钮为「退出对局」（再来一局暂未支持）
class _BoardView extends StatelessWidget {
  const _BoardView({
    required this.controller,
    required this.selected,
    required this.legalTargets,
    required this.pendingMove,
    required this.checkFlashTrigger,
    required this.onCellTap,
    required this.onCancelMove,
    required this.onConfirmMove,
    required this.onRequestUndo,
    required this.onResign,
    required this.onExit,
  });

  final ChessOnlineController controller;

  /// 当前选中的己方棋子；null 表示无选中
  final ChessPos? selected;

  /// 选中棋子的合法落点集合
  final Set<ChessPos> legalTargets;

  /// 待确认走法；非空时显示确认行
  final ChessMove? pendingMove;

  /// 「将军」提示触发计数
  final int checkFlashTrigger;

  /// 点击棋盘格回调
  final void Function(ChessPos pos) onCellTap;

  /// 点击「取消」回调：清除待确认走法
  final VoidCallback onCancelMove;

  /// 点击「确认走子」回调：提交房主校验
  final VoidCallback onConfirmMove;

  /// 点击「悔棋」回调：向对方发起悔棋请求
  final VoidCallback onRequestUndo;

  /// 点击「认输」回调：确认后判对方获胜
  final VoidCallback onResign;

  /// 终局后点击「退出对局」回调
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final turnColor = controller.turnColor;
    final isOver = controller.winnerSeat != null;
    final ended = controller.gameEndedText != null;
    // 终局（含无胜负终止）后提示胜方/结束；对局中提示等待对象
    final String turnTitle;
    final String turnSubtitle;
    if (isOver) {
      turnTitle = '${controller.winnerText ?? ''}获胜';
      turnSubtitle = '对局结束';
    } else if (ended) {
      turnTitle = '对局结束';
      turnSubtitle = '本局已终止';
    } else {
      turnTitle = turnColor == ChessColor.red ? '红方' : '黑方';
      turnSubtitle = controller.isMyTurn ? '轮到你走子' : '等待对方走子';
    }

    return SizedBox.expand(
      child: Stack(
        children: [
          PageContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 行棋提示卡：图标颜色跟随行棋方棋子色（红/黑）
                TurnCard(
                  icon: Icons.circle_rounded,
                  iconColor: turnColor == ChessColor.red
                      ? ChessPieceColors.red
                      : ChessPieceColors.black,
                  subtitle: turnSubtitle,
                  title: turnTitle,
                  titleKey: ValueKey(turnTitle),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ChessBoardCanvas(
                    board: controller.board,
                    selected: selected,
                    legalTargets: legalTargets,
                    pendingMove: pendingMove,
                    onCellTap: onCellTap,
                    // 执黑方整盘旋转 180°：自己的棋子显示在屏幕下方，
                    // 棋子相对位置与真实对面视角一致（文字朝向不变）
                    flipped: controller.myColor == ChessColor.black,
                  ),
                ),
                const SizedBox(height: 16),
                ConfirmMoveRow(
                  visible: pendingMove != null,
                  onCancelMove: onCancelMove,
                  onConfirmMove: onConfirmMove,
                ),
                const SizedBox(height: 12),
                if (isOver || ended)
                  // 终局：退出对局（再来一局暂未支持）
                  PrimaryButton(
                    label: '退出对局',
                    icon: Icons.logout_rounded,
                    onPressed: onExit,
                  )
                else ...[
                  // 悔棋：仅对方回合可发起（悔自己的上一手），
                  // 等对方应答期间/无子可悔/轮到自己走子时禁用
                  PrimaryButton(
                    label: controller.undoState == UndoState.awaitingPeer
                        ? '等待对方应答…'
                        : '悔棋',
                    icon: Icons.undo_rounded,
                    onPressed:
                        controller.undoState == UndoState.idle &&
                            controller.moves.isNotEmpty &&
                            !controller.isMyTurn
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
          // 「将军」提示覆盖层：不拦截触摸，仅做视觉提醒
          IgnorePointer(
            child: Center(
              child: CheckFlashText(trigger: checkFlashTrigger),
            ),
          ),
        ],
      ),
    );
  }
}
