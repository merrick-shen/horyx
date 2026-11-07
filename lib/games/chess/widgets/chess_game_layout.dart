import 'package:flutter/material.dart';

import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/models/chess_piece.dart';
import 'package:horyx/games/chess/widgets/chess_board_canvas.dart';
import 'package:horyx/shared/widgets/confirm_move_row.dart';
import 'package:horyx/shared/widgets/hint_overlay.dart';
import 'package:horyx/shared/widgets/page_content.dart';
import 'package:horyx/shared/widgets/turn_card.dart';

/// 象棋对局布局（本地与联机对局视图共用）：
/// 行棋提示卡 + 棋盘 + 落子确认行 + 底部按钮插槽 + 「将军」提示覆盖层。
/// 两视图仅行棋卡文案（本地"当前行棋"/联机"轮到你走子"等）、执黑视角
/// 棋盘翻转与底部按钮集不同，以 [turnTitle]/[turnSubtitle]/[flipped]/
/// [actions] 参数注入
class ChessGameLayout extends StatelessWidget {
  const ChessGameLayout({
    super.key,
    required this.board,
    required this.turn,
    required this.turnTitle,
    required this.turnSubtitle,
    required this.selected,
    required this.legalTargets,
    required this.pendingMove,
    required this.checkFlashTrigger,
    required this.onCellTap,
    required this.onCancelMove,
    required this.onConfirmMove,
    required this.actions,
    this.flipped = false,
    this.lastMove,
    this.capturedPiece,
    this.lastMoveSeq = 0,
  });

  final ChessBoard board;

  /// 当前行棋方（行棋卡图标颜色跟随棋子色红/黑）
  final ChessColor turn;

  /// 行棋卡标题与副标题（由页面按语义组装）
  final String turnTitle;
  final String turnSubtitle;

  /// 当前选中的己方棋子；null 表示无选中
  final ChessPos? selected;

  /// 选中棋子的合法落点集合
  final Set<ChessPos> legalTargets;

  /// 待确认走法；非空时显示确认行
  final ChessMove? pendingMove;

  /// 「将军」提示触发计数（页面层每检测到将军递增一次）
  final int checkFlashTrigger;

  /// 点击棋盘格回调（吸附到最近交点后的格坐标；棋盘外框以外点击不回调）
  final void Function(ChessPos pos) onCellTap;

  /// 点击「取消」回调：清除待确认走法
  final VoidCallback onCancelMove;

  /// 点击「确认走子」回调：执行/提交待确认走法
  final VoidCallback onConfirmMove;

  /// 底部按钮插槽：本地为悔棋/再来一局，联机为悔棋协商/认输/退出操作组
  final Widget actions;

  /// 执黑方整盘旋转 180°（联机客户端视角），本地不翻转
  final bool flipped;

  /// 最近一步走法（棋盘走子动画用，见 [ChessBoardCanvas.lastMove]）
  final ChessMove? lastMove;

  /// 最近一步被吃的棋子（动画期间暂留显示在终点位，见
  /// [ChessBoardCanvas.capturedPiece]）
  final ChessPiece? capturedPiece;

  /// 最近一步的触发序号（见 [ChessBoardCanvas.lastMoveSeq]）
  final int lastMoveSeq;

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
                  subtitle: turnSubtitle,
                  title: turnTitle,
                  titleKey: ValueKey(turnTitle),
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
                    flipped: flipped,
                  ),
                ),
                const SizedBox(height: 16),
                ConfirmMoveRow(
                  visible: pendingMove != null,
                  onCancelMove: onCancelMove,
                  onConfirmMove: onConfirmMove,
                ),
                const SizedBox(height: 12),
                actions,
              ],
            ),
          ),
          // 「将军」提示覆盖层：不拦截触摸，仅做视觉提醒
          HintOverlay(
            trigger: checkFlashTrigger,
            text: '將軍',
            accentColor: ChessPieceColors.red,
            fontSize: 64,
            letterSpacing: 10,
          ),
        ],
      ),
    );
  }
}
