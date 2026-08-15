import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 五子棋棋盘：按路数绘制网格线与星位
/// 静态阶段仅展示空盘，落子绘制待玩法开发接入
class GomokuBoard extends StatelessWidget {
  const GomokuBoard({super.key, required this.size});

  /// 棋盘路数（15 标准盘 / 19 大盘）
  final int size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AspectRatio(
      // 棋盘保持正方形
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: palette.surfaceBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.stroke),
        ),
        // 裁剪保证绘制内容不溢出圆角
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: CustomPaint(
            size: Size.infinite,
            painter: _BoardPainter(
              linesColor: palette.stroke,
              size: size,
            ),
          ),
        ),
      ),
    );
  }
}

/// 棋盘画笔：网格线 + 星位
class _BoardPainter extends CustomPainter {
  _BoardPainter({required this.linesColor, required this.size});

  /// 网格线颜色
  final Color linesColor;

  /// 棋盘路数
  final int size;

  /// 各路数对应的星位坐标（0 起算）
  /// 15 路：四角星 + 天元；19 路：九星位
  static const Map<int, List<(int, int)>> _starPoints = {
    15: [(3, 3), (3, 11), (7, 7), (11, 3), (11, 11)],
    19: [
      (3, 3), (3, 9), (3, 15),
      (9, 3), (9, 9), (9, 15),
      (15, 3), (15, 9), (15, 15),
    ],
  };

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final paint = Paint()
      ..color = linesColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // 边距取一格宽度，保证四周留白与内部格距一致
    final cell = canvasSize.width / (size + 1);
    final board = cell * (size - 1);
    final origin = (canvasSize.width - board) / 2;

    // 网格线：size 条横线 + size 条竖线
    for (int i = 0; i < size; i++) {
      final offset = origin + cell * i;
      canvas.drawLine(
        Offset(origin, offset),
        Offset(origin + board, offset),
        paint,
      );
      canvas.drawLine(
        Offset(offset, origin),
        Offset(offset, origin + board),
        paint,
      );
    }

    // 星位：实心圆点，半径随格距缩放
    final stars = _starPoints[size] ?? const <(int, int)>[];
    if (stars.isNotEmpty) {
      final dotPaint = Paint()
        ..color = linesColor
        ..style = PaintingStyle.fill;
      final radius = cell * 0.11;
      for (final (col, row) in stars) {
        canvas.drawCircle(
          Offset(origin + cell * col, origin + cell * row),
          radius,
          dotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BoardPainter oldDelegate) =>
      oldDelegate.size != size || oldDelegate.linesColor != linesColor;
}
