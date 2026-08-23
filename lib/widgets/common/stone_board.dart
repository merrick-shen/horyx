import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 棋盘上的一颗棋子：位置 + 颜色
/// 颜色需显式存储而非按落子顺序推导：
/// 围棋存在提子，落子序列无法从奇偶推断黑白
typedef Stone = (int col, int row, bool black);

/// 黑白棋子棋盘通用组件：网格线 + 星位 + 棋子绘制，支持点击交叉点
/// 五子棋 / 围棋等落子类棋盘游戏共用
/// 预选棋子（落子确认前）以半透明展示
class StoneBoard extends StatelessWidget {
  const StoneBoard({
    super.key,
    required this.size,
    this.stones = const [],
    this.pending,
    this.onCellTap,
  });

  /// 棋盘路数（9/13/19 围棋、15/19 五子棋等）
  final int size;

  /// 已确认的棋子集合（颜色显式）
  final List<Stone> stones;

  /// 预选棋子（点击棋盘后、确认前，颜色由执子方决定）；null 表示无预选
  final Stone? pending;

  /// 点击棋盘回调：换算为最近交叉点坐标（col/row 从 0 起）
  final void Function(int col, int row)? onCellTap;

  /// 黑子/白子固有色（棋子颜色不随主题变化，仅描边随主题取色）
  /// 对外公开供执子指示等处复用，保证全局棋子颜色一致
  static const Color blackStone = Color(0xFF17181D);
  static const Color whiteStone = Color(0xFFFFFFFF);

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

  /// 已确认的棋子集合
  final List<Stone> stones;

  /// 预选棋子
  final Stone? pending;

  /// 各路数对应的星位坐标（0 起算）
  /// 9/13 路：四角星 + 天元；15 路：四角星 + 天元；19 路：九星位
  static const Map<int, List<(int, int)>> _starPoints = {
    9: [(2, 2), (2, 6), (4, 4), (6, 2), (6, 6)],
    13: [(3, 3), (3, 9), (6, 6), (9, 3), (9, 9)],
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

    // 已确认棋子：颜色显式存储
    for (final (col, row, black) in stones) {
      _drawStone(
        canvas,
        center: Offset(origin + cell * col, origin + cell * row),
        radius: cell * 0.42,
        black: black,
        opacity: 1,
      );
    }

    // 预选棋子：半透明示意「待确认」
    final selected = pending;
    if (selected != null) {
      final (col, row, black) = selected;
      _drawStone(
        canvas,
        center: Offset(origin + cell * col, origin + cell * row),
        radius: cell * 0.42,
        black: black,
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
      ..color = (black ? StoneBoard.blackStone : StoneBoard.whiteStone)
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
      // 逐项比较内容而非长度：联机悔棋与落子可能同帧到达，
      // 棋子先移除后新增时长度不变，仅比长度会漏掉这次重绘
      // Stone 为 record 自带值语义，可安全逐项 == 比较
      !listEquals(oldDelegate.stones, stones) ||
      oldDelegate.pending != pending;
}
