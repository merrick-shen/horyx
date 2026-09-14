import 'package:flutter/material.dart';

import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/models/chess_piece.dart';
import 'package:horyx/games/chess/widgets/chess_board_canvas.dart';
import 'package:horyx/games/chess/widgets/chess_check_flash.dart';
import 'package:horyx/shared/widgets/confirm_move_row.dart';
import 'package:horyx/shared/widgets/page_content.dart';
import 'package:horyx/shared/widgets/primary_button.dart';
import 'package:horyx/shared/widgets/turn_card.dart';

/// 中国象棋 - 对局视图：当前行棋提示 + 棋盘（手势交互）+ 落子确认行 + 操作按钮
/// 交互逻辑（选子/走子/终局判定）在页面层，本视图只做展示与点击转发：
/// 棋盘绘制与手势命中见共享的 [ChessBoardCanvas]，
/// [checkFlashTrigger] 递增时在棋盘中央播放「将军」渐现渐隐提示
class ChessBoardView extends StatelessWidget {
  const ChessBoardView({
    super.key,
    required this.board,
    required this.turn,
    required this.selected,
    required this.legalTargets,
    required this.pendingMove,
    required this.checkFlashTrigger,
    required this.gameOver,
    required this.canUndo,
    required this.onCellTap,
    required this.onCancelMove,
    required this.onConfirmMove,
    required this.onUndo,
    required this.onRestart,
    this.lastMove,
    this.capturedPiece,
    this.lastMoveSeq = 0,
  });

  final ChessBoard board;

  /// 当前行棋方（执子卡展示）
  final ChessColor turn;

  /// 当前选中的己方棋子；null 表示无选中
  final ChessPos? selected;

  /// 选中棋子的合法落点集合
  final Set<ChessPos> legalTargets;

  /// 待确认走法；非空时显示确认行
  final ChessMove? pendingMove;

  /// 「将军」提示触发计数（页面层每检测到将军递增一次）
  final int checkFlashTrigger;

  /// 是否已终局（true 时悔棋按钮替换为再来一局）
  final bool gameOver;

  /// 是否有子可悔（无走子历史时悔棋按钮禁用）
  final bool canUndo;

  /// 最近一步走法（棋盘走子动画用，见 [ChessBoardCanvas.lastMove]）
  final ChessMove? lastMove;

  /// 最近一步被吃的棋子（动画期间暂留显示在终点位，见
  /// [ChessBoardCanvas.capturedPiece]）
  final ChessPiece? capturedPiece;

  /// 最近一步的触发序号（见 [ChessBoardCanvas.lastMoveSeq]）
  final int lastMoveSeq;

  /// 点击棋盘格回调（吸附到最近交点后的格坐标；棋盘外框以外点击不回调）
  final void Function(ChessPos pos) onCellTap;

  /// 点击「取消」回调：清除待确认走法
  final VoidCallback onCancelMove;

  /// 点击「确认走子」回调：执行待确认走法
  final VoidCallback onConfirmMove;

  /// 点击「悔棋」回调：撤销最近一步
  final VoidCallback onUndo;

  /// 终局后点击「再来一局」回调：重开新对局
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
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
                  iconColor: turn == ChessColor.red
                      ? ChessPieceColors.red
                      : ChessPieceColors.black,
                  subtitle: '当前行棋',
                  title: turn == ChessColor.red ? '红方' : '黑方',
                  titleKey: ValueKey(turn),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ChessBoardCanvas(
                    board: board,
                    selected: selected,
                    legalTargets: legalTargets,
                    pendingMove: pendingMove,
                    onCellTap: onCellTap,
                    lastMove: lastMove,
                    capturedPiece: capturedPiece,
                    lastMoveSeq: lastMoveSeq,
                  ),
                ),
                const SizedBox(height: 16),
                ConfirmMoveRow(
                  visible: pendingMove != null,
                  onCancelMove: onCancelMove,
                  onConfirmMove: onConfirmMove,
                ),
                const SizedBox(height: 12),
                if (gameOver)
                  // 终局：悔棋替换为再来一局，方便查看棋型后重开
                  PrimaryButton(
                    label: '再来一局',
                    icon: Icons.refresh_rounded,
                    onPressed: onRestart,
                  )
                else
                  // 对局中：无子可悔时按钮禁用（灰底不可点击）
                  PrimaryButton(
                    label: '悔棋',
                    icon: Icons.undo_rounded,
                    onPressed: canUndo ? onUndo : null,
                  ),
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
