import 'package:flutter/material.dart';

import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/widgets/chess_board_painter.dart';
import 'package:horyx/shared/theme/app_theme.dart';

/// 象棋棋盘画布：棋盘按可用空间等比缩放 + 点击手势命中
/// （本地对局视图与联机对局视图共用）；
/// 几何换算与绘制来自 [ChessBoardGeometry]/[ChessBoardPainter]，
/// 点击经换算转为格坐标后回调 [onCellTap]（棋盘外点击不回调）
class ChessBoardCanvas extends StatelessWidget {
  const ChessBoardCanvas({
    super.key,
    required this.board,
    required this.selected,
    required this.legalTargets,
    required this.pendingMove,
    required this.onCellTap,
    this.flipped = false,
  });

  final ChessBoard board;

  /// 当前选中的己方棋子；null 表示无选中
  final ChessPos? selected;

  /// 选中棋子的合法落点集合
  final Set<ChessPos> legalTargets;

  /// 待确认走法；非空时绘制待确认标记
  final ChessMove? pendingMove;

  /// 点击棋盘格回调（换算后的格坐标）
  final void Function(ChessPos pos) onCellTap;

  /// 是否整盘旋转 180°（联机执黑方为 true：己方棋子显示在屏幕下方）
  final bool flipped;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final geometry = ChessBoardGeometry.forSize(
            constraints.biggest,
            flipped: flipped,
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
    );
  }
}
