import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 五子棋棋盘：网格线 + 星位 + 棋子绘制，支持点击交叉点
/// 棋子黑白交替（先手黑），预选棋子半透明展示待确认状态
class GomokuBoard extends StatelessWidget {
  const GomokuBoard({
    super.key,
    required this.size,
    this.stones = const [],
    this.pending,
    this.onCellTap,
  });

  /// 棋盘路数（15 标准盘 / 19 大盘）
  final int size;

  /// 已确认落子序列（索引奇偶决定黑白：0=黑 1=白）
  final List<(int, int)> stones;

  /// 预选落子位置（点击棋盘后、确认前）；null 表示无预选
  final (int, int)? pending;

  /// 点击棋盘回调：换算为最近交叉点坐标（col/row 从 0 起）
  final void Function(int col, int row)? onCellTap;

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
        // LayoutBuilder 提供绘制区域尺寸，用于点击坐标换算
        child: LayoutBuilder(
          builder: (context, constraints) {
            final boardWidth = constraints.maxWidth;
            // 交叉点间距：画布宽 / (路数 + 1)，首个交叉点位于一格边距处
            final cell = boardWidth / (size + 1);

            return GestureDetector(
              // opaque 保证棋盘空白区域也可响应点击
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) =>
                  _handleTap(details.localPosition, cell),
              // 裁剪保证绘制内容不溢出圆角
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _BoardPainter(
                    linesColor: palette.stroke,
                    size: size,
                    stones: stones,
                    pending: pending,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 将点击坐标换算为最近交叉点（四舍五入，边界钳制在棋盘内）
  void _handleTap(Offset position, double cell) {
    final callback = onCellTap;
    if (callback == null) return;

    // 交叉点坐标 = 一格边距 + col*cell，反推 col 并钳制到 [0, size-1]
    int clampIndex(double raw) =>
        raw.round().clamp(0, size - 1);

    final col = clampIndex(position.dx / cell - 1);
    final row = clampIndex(position.dy / cell - 1);
    callback(col, row);
  }
}

/// 棋盘画笔：网格线 + 星位 + 黑白棋子
class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.linesColor,
    required this.size,
    required this.stones,
    required this.pending,
  });

  /// 网格线颜色
  final Color linesColor;

  /// 棋盘路数
  final int size;

  /// 已确认落子序列
  final List<(int, int)> stones;

  /// 预选落子位置
  final (int, int)? pending;

  /// 黑子/白子固有色（棋子颜色不随主题变化，仅描边随主题取色）
  static const Color _blackStone = Color(0xFF17181D);
  static const Color _whiteStone = Color(0xFFFFFFFF);

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
    final gridPaint = Paint()
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
        gridPaint,
      );
      canvas.drawLine(
        Offset(offset, origin),
        Offset(offset, origin + board),
        gridPaint,
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

    // 已确认棋子：索引奇偶决定黑白（先手黑）
    for (int i = 0; i < stones.length; i++) {
      final (col, row) = stones[i];
      _drawStone(
        canvas,
        center: Offset(origin + cell * col, origin + cell * row),
        radius: cell * 0.42,
        black: i.isEven,
        opacity: 1,
      );
    }

    // 预选棋子：半透明示意「待确认」，颜色随当前执子方
    final selected = pending;
    if (selected != null) {
      final (col, row) = selected;
      _drawStone(
        canvas,
        center: Offset(origin + cell * col, origin + cell * row),
        radius: cell * 0.42,
        black: stones.length.isEven,
        opacity: 0.45,
      );
    }
  }

  /// 绘制单颗棋子：实心圆 + 主题描边（区分棋盘底色）
  void _drawStone(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required bool black,
    required double opacity,
  }) {
    final fill = Paint()
      ..color = (black ? _blackStone : _whiteStone)
          .withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, fill);

    // 描边让白子在浅色棋盘、黑子在深色棋盘上轮廓清晰
    final stroke = Paint()
      ..color = linesColor.withValues(alpha: opacity)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, stroke);
  }

  @override
  bool shouldRepaint(_BoardPainter oldDelegate) =>
      oldDelegate.size != size ||
      oldDelegate.linesColor != linesColor ||
      oldDelegate.stones.length != stones.length ||
      oldDelegate.pending != pending;
}
