import 'package:flutter/material.dart';

import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/models/chess_piece.dart';
import 'package:horyx/games/chess/widgets/chess_board_painter.dart';
import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/widgets/confirm_move_row.dart';
import 'package:horyx/shared/widgets/page_content.dart';
import 'package:horyx/shared/widgets/turn_card.dart';

/// 中国象棋 - 对局视图：当前行棋提示 + 棋盘（手势交互）+ 落子确认行
/// 交互逻辑（选子/走子/终局判定）在页面层，本视图只做展示与点击转发：
/// 手势经几何换算转为格坐标后回调 [onCellTap]（棋盘外点击不回调）
class ChessBoardView extends StatelessWidget {
  const ChessBoardView({
    super.key,
    required this.board,
    required this.turn,
    required this.selected,
    required this.legalTargets,
    required this.pendingMove,
    required this.onCellTap,
    required this.onCancelMove,
    required this.onConfirmMove,
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

  /// 点击棋盘格回调（换算后的格坐标；点击棋盘外不回调）
  final void Function(ChessPos pos) onCellTap;

  /// 点击「取消」回调：清除待确认走法
  final VoidCallback onCancelMove;

  /// 点击「确认走子」回调：执行待确认走法
  final VoidCallback onConfirmMove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox.expand(
      child: PageContent(
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
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final geometry = ChessBoardGeometry.forSize(
                      constraints.biggest,
                    );
                    return GestureDetector(
                      onTapUp: (details) {
                        // 点击换算为格坐标，棋盘外不响应
                        final pos = geometry.offsetToPos(details.localPosition);
                        if (pos != null) onCellTap(pos);
                      },
                      child: CustomPaint(
                        size: geometry.boardSize,
                        painter: ChessBoardPainter(
                          board: board,
                          geometry: geometry,
                          surfaceColor: palette.surfaceBg,
                          strokeColor: palette.stroke,
                          textSecondaryColor: palette.textSecondary,
                          primaryColor: palette.primary,
                          selected: selected,
                          legalTargets: legalTargets,
                          pendingMove: pendingMove,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            ConfirmMoveRow(
              visible: pendingMove != null,
              onCancelMove: onCancelMove,
              onConfirmMove: onConfirmMove,
            ),
          ],
        ),
      ),
    );
  }
}
