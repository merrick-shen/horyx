import 'package:flutter/material.dart';

import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/models/chess_piece.dart';

/// 棋盘几何换算：逻辑格坐标 ↔ 屏幕像素，绘制与手势命中共用同一套换算
/// 屏幕方向约定：row 0（红方底线）画在底部，符合双人同屏的红方视角直觉
class ChessBoardGeometry {
  ChessBoardGeometry._({required this.cell, required this.margin})
      : boardSize = Size(
          (ChessBoard.cols - 1) * cell + margin * 2,
          (ChessBoard.rows - 1) * cell + margin * 2,
        );

  /// 格距（相邻线路间距，棋盘等比缩放的最小单位）
  final double cell;

  /// 线路区距棋盘边缘的留白（容纳棋子半径与外框）
  final double margin;

  /// 棋盘整体尺寸
  final Size boardSize;

  /// 线路区距边缘的留白占格距比例（比例化保证任意尺寸下观感一致）
  static const double _marginRatio = 0.55;

  /// 按可用空间计算几何：
  /// 棋盘总宽 = (cols-1)*cell + 2*margin = 9.1*cell，总高 = 10.1*cell，
  /// cell 取宽高约束下较小者，保证棋盘完整可见且等比缩放
  factory ChessBoardGeometry.forSize(Size available) {
    final w = available.width / (ChessBoard.cols - 1 + _marginRatio * 2);
    final h = available.height / (ChessBoard.rows - 1 + _marginRatio * 2);
    final cell = w < h ? w : h;
    return ChessBoardGeometry._(cell: cell, margin: cell * _marginRatio);
  }

  /// 格坐标 → 屏幕中心点（row 0 在屏幕底部）
  Offset posToOffset(ChessPos pos) {
    final (col, row) = pos;
    return Offset(
      margin + col * cell,
      margin + (ChessBoard.rows - 1 - row) * cell,
    );
  }

  /// 屏幕点 → 最近格坐标；超出棋盘范围返回 null（阶段 6 手势命中使用）
  ChessPos? offsetToPos(Offset o) {
    final col = ((o.dx - margin) / cell).round();
    final row = ChessBoard.rows - 1 - ((o.dy - margin) / cell).round();
    if (col < 0 || col >= ChessBoard.cols || row < 0 || row >= ChessBoard.rows) {
      return null;
    }
    return (col, row);
  }
}

/// 棋盘绘制器：底板、线路、河界、九宫、炮兵位标记、全部棋子与交互高亮
/// 线路颜色由 view 层从当前主题调色板注入（painter 无 BuildContext）；
/// 棋子的米色底面与红黑字色为游戏内容色（模拟真实木质棋面），
/// 属于素材色而非主题语义色，故按固定色值绘制
class ChessBoardPainter extends CustomPainter {
  ChessBoardPainter({
    required this.board,
    required this.geometry,
    required this.surfaceColor,
    required this.strokeColor,
    required this.textSecondaryColor,
    required this.primaryColor,
    this.selected,
    this.legalTargets = const {},
    this.pendingMove,
  });

  final ChessBoard board;
  final ChessBoardGeometry geometry;

  /// 主题色（view 层经 context.palette 注入）
  final Color surfaceColor; // 底板面板色
  final Color strokeColor; // 线路与标记色
  final Color textSecondaryColor; // 河界文字色
  final Color primaryColor; // 选中/走点/预选等交互高亮色

  /// 当前选中的己方棋子；null 表示无选中
  final ChessPos? selected;

  /// 选中棋子的合法落点集合（空格画走点、敌子格画可吃环）
  final Set<ChessPos> legalTargets;

  /// 待确认走法（ConfirmMoveRow 出现时高亮起点与终点）
  final ChessMove? pendingMove;

  /// 棋子内容色统一引用模型层常量（执子卡共用同一来源）
  static const Color _pieceFace = ChessPieceColors.face;
  static const Color _redPiece = ChessPieceColors.red;
  static const Color _blackPiece = ChessPieceColors.black;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBase(canvas, size);
    _paintGrid(canvas);
    _paintPalaceDiagonals(canvas);
    _paintRiverText(canvas);
    _paintPositionMarks(canvas);
    _paintPieces(canvas);
    // 高亮最后绘制，确保叠在棋子上层
    _paintHighlights(canvas);
  }

  /// 底板：圆角面板 + 描边外框
  void _paintBase(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(geometry.cell * 0.18),
    );
    canvas.drawRRect(rrect, Paint()..color = surfaceColor);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = geometry.cell * 0.045
        ..color = strokeColor,
    );
  }

  /// 线路：10 条横线全宽；9 条竖线中，中间 7 条被河界断开为上下两段
  void _paintGrid(Canvas canvas) {
    final paint = Paint()
      ..strokeWidth = geometry.cell * 0.022
      ..color = strokeColor;
    final m = geometry.margin;
    final c = geometry.cell;
    final boardW = (ChessBoard.cols - 1) * c;
    final boardH = (ChessBoard.rows - 1) * c;

    // 横线（屏幕每行一条）
    for (var i = 0; i < ChessBoard.rows; i++) {
      final y = m + i * c;
      canvas.drawLine(Offset(m, y), Offset(m + boardW, y), paint);
    }
    // 竖线：左右两条边线贯通，中间 7 条因河界分两段
    for (var col = 0; col < ChessBoard.cols; col++) {
      final x = m + col * c;
      if (col == 0 || col == ChessBoard.cols - 1) {
        canvas.drawLine(Offset(x, m), Offset(x, m + boardH), paint);
      } else {
        canvas.drawLine(Offset(x, m), Offset(x, m + 4 * c), paint);
        canvas.drawLine(Offset(x, m + 5 * c), Offset(x, m + boardH), paint);
      }
    }
  }

  /// 九宫斜线（红宫 row 0-2 在屏幕底部，黑宫 row 7-9 在顶部）
  void _paintPalaceDiagonals(Canvas canvas) {
    final paint = Paint()
      ..strokeWidth = geometry.cell * 0.022
      ..color = strokeColor;
    for (final (from, to) in const [
      ((3, 0), (5, 2)), // 红宫
      ((5, 0), (3, 2)),
      ((3, 7), (5, 9)), // 黑宫
      ((5, 7), (3, 9)),
    ]) {
      canvas.drawLine(geometry.posToOffset(from), geometry.posToOffset(to), paint);
    }
  }

  /// 河界文字：「楚河」「汉界」分列中线两侧
  void _paintRiverText(Canvas canvas) {
    final style = TextStyle(
      color: textSecondaryColor,
      fontSize: geometry.cell * 0.5,
      fontWeight: FontWeight.w600,
      letterSpacing: geometry.cell * 0.18,
    );
    final midY = geometry.margin + 4.5 * geometry.cell;
    _paintCenteredText(canvas, '楚河', Offset(geometry.margin + 2 * geometry.cell, midY), style);
    _paintCenteredText(canvas, '汉界', Offset(geometry.margin + 6 * geometry.cell, midY), style);
  }

  /// 炮位/兵位标记：交点四角小折线，边线交点只画内侧半边
  void _paintPositionMarks(Canvas canvas) {
    const positions = [
      (1, 2), (7, 2), (1, 7), (7, 7), // 炮位
      (0, 3), (2, 3), (4, 3), (6, 3), (8, 3), // 兵位
      (0, 6), (2, 6), (4, 6), (6, 6), (8, 6), // 卒位
    ];
    final paint = Paint()
      ..strokeWidth = geometry.cell * 0.022
      ..color = strokeColor;
    final d1 = geometry.cell * 0.08; // 折线起点距交点
    final d2 = geometry.cell * 0.2; // 折线长度
    for (final pos in positions) {
      final (col, _) = pos;
      final p = geometry.posToOffset(pos);
      _drawMarkCorners(canvas, p, d1, d2, paint,
          left: col > 0, right: col < ChessBoard.cols - 1);
    }
  }

  /// 在交点四象限画折线标记；left/right 控制是否绘制左/右两侧（边线只画内侧）
  void _drawMarkCorners(
    Canvas canvas,
    Offset p,
    double d1,
    double d2,
    Paint paint, {
    required bool left,
    required bool right,
  }) {
    // 左右两侧各含上下两个象限的 (dx, dy) 方向
    final quadrants = [
      if (left) ...[(-1, -1), (-1, 1)],
      if (right) ...[(1, -1), (1, 1)],
    ];
    for (final (sx, sy) in quadrants) {
      // 横线段 + 竖线段组成角折线
      canvas.drawLine(
        Offset(p.dx + sx * d1, p.dy + sy * d2),
        Offset(p.dx + sx * d2, p.dy + sy * d2),
        paint,
      );
      canvas.drawLine(
        Offset(p.dx + sx * d2, p.dy + sy * d2),
        Offset(p.dx + sx * d2, p.dy + sy * d1),
        paint,
      );
    }
  }

  /// 全部棋子：米色圆面 + 红黑描边、内圈细线与居中汉字
  void _paintPieces(Canvas canvas) {
    final radius = geometry.cell * 0.45;
    final facePaint = Paint()..color = _pieceFace;
    for (var row = 0; row < ChessBoard.rows; row++) {
      for (var col = 0; col < ChessBoard.cols; col++) {
        final piece = board.pieceAt((col, row));
        if (piece == null) continue;
        final center = geometry.posToOffset((col, row));
        final color = piece.color == ChessColor.red ? _redPiece : _blackPiece;

        // 轻微下移的阴影提升立体感
        canvas.drawCircle(
          center + Offset(0, geometry.cell * 0.03),
          radius,
          Paint()..color = const Color(0x33000000),
        );
        canvas.drawCircle(center, radius, facePaint);
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = geometry.cell * 0.035
            ..color = color,
        );
        // 内圈细线（传统棋子样式）
        canvas.drawCircle(
          center,
          radius * 0.82,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = geometry.cell * 0.018
            ..color = color.withValues(alpha: 0.55),
        );
        _paintCenteredText(
          canvas,
          piece.label,
          center,
          TextStyle(
            color: color,
            fontSize: geometry.cell * 0.52,
            fontWeight: FontWeight.w800,
          ),
        );
      }
    }
  }

  /// 交互高亮：选中棋子环、合法走点、待确认走法起终点
  /// 可吃敌子格不做任何高亮（敌子本身即视觉提示）；确认走法时走点保持显示
  void _paintHighlights(Canvas canvas) {
    // 描边环绘制辅助（局部函数声明，避免闭包赋值的 lint 告警）
    Paint ringPaint(double width, Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;

    // 选中棋子高亮环
    final sel = selected;
    if (sel != null) {
      canvas.drawCircle(
        geometry.posToOffset(sel),
        geometry.cell * 0.52,
        ringPaint(geometry.cell * 0.045, primaryColor),
      );
      // 合法走点：仅空格画半透明圆点（落点上有棋子则不画）
      final dotPaint = Paint()
        ..color = primaryColor.withValues(alpha: 0.55);
      for (final target in legalTargets) {
        if (board.pieceAt(target) != null) continue;
        canvas.drawCircle(
          geometry.posToOffset(target),
          geometry.cell * 0.15,
          dotPaint,
        );
      }
    }

    // 待确认走法：起点与终点高亮环（尺寸与选中环一致；不 return，走点提示保持显示）
    final pending = pendingMove;
    if (pending != null) {
      canvas.drawCircle(
        geometry.posToOffset(pending.from),
        geometry.cell * 0.52,
        ringPaint(geometry.cell * 0.045, primaryColor),
      );
      canvas.drawCircle(
        geometry.posToOffset(pending.to),
        geometry.cell * 0.52,
        ringPaint(geometry.cell * 0.045, primaryColor),
      );
    }
  }

  /// 居中绘制文字
  void _paintCenteredText(Canvas canvas, String text, Offset center, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant ChessBoardPainter oldDelegate) =>
      oldDelegate.board != board ||
      oldDelegate.geometry != geometry ||
      oldDelegate.surfaceColor != surfaceColor ||
      oldDelegate.strokeColor != strokeColor ||
      oldDelegate.textSecondaryColor != textSecondaryColor ||
      oldDelegate.primaryColor != primaryColor ||
      oldDelegate.selected != selected ||
      oldDelegate.legalTargets != legalTargets ||
      oldDelegate.pendingMove != pendingMove;
}
