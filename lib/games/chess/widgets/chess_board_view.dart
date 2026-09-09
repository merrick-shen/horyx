import 'package:flutter/material.dart';

import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/widgets/chess_board_painter.dart';
import 'package:horyx/shared/theme/app_theme.dart';

/// 棋盘视图：按可用空间等比缩放的静态棋盘
/// 阶段 5 为纯展示（无交互）；几何换算与绘制器已封装，
/// 阶段 6 的手势命中（ChessBoardGeometry.offsetToPos）直接复用
class ChessBoardView extends StatelessWidget {
  const ChessBoardView({super.key, required this.board});

  final ChessBoard board;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = ChessBoardGeometry.forSize(constraints.biggest);
        return Center(
          child: CustomPaint(
            size: geometry.boardSize,
            painter: ChessBoardPainter(
              board: board,
              geometry: geometry,
              surfaceColor: palette.surfaceBg,
              strokeColor: palette.stroke,
              textSecondaryColor: palette.textSecondary,
            ),
          ),
        );
      },
    );
  }
}
