import 'package:flutter/material.dart';

import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/models/chess_piece.dart';
import 'package:horyx/games/chess/widgets/chess_board_geometry.dart';

/// 棋盘绘制器：底板、线路、河界、九宫、炮兵位标记、全部棋子与交互高亮
/// 线路颜色由 view 层从当前主题调色板注入（painter 无 BuildContext）；
/// 棋子的米色底面与红黑字色为游戏内容色（模拟真实木质棋面），
/// 属于素材色而非主题语义色，故按固定色值绘制
/// 格坐标↔像素换算见 [ChessBoardGeometry]（chess_board_geometry.dart）
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
    this.lastMove,
    this.capturedPiece,
    this.animProgress = 1,
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

  /// 最近一步走法（走子动画）：非 null 且 [animProgress] < 1 时，
  /// 终点棋子跳过原位绘制、改画在起→终点插值位置并浮于其他棋子上层；
  /// 动画结束（progress = 1）后按原位正常绘制
  final ChessMove? lastMove;

  /// 最近一步被吃的棋子（走子动画展示用；无吃子为 null）：动画播放中
  /// 暂留绘制在终点位（垫在移动棋子下方），动画结束随动画层一并消失——
  /// 消失瞬间它已被移动棋子完全覆盖，观感是"被吃掉"而非凭空消失
  final ChessPiece? capturedPiece;

  /// 最近一步的动画进度（0..1，1 表示未在动画中或已播完）；
  /// 插值在格坐标语义下进行（经 geometry 换算到当前像素），
  /// 画布尺寸变化时逐帧按最新几何重算，任意屏幕尺寸下观感一致
  final double animProgress;

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
    // 移动中的棋子最后绘制：浮于全部棋子与高亮之上（滑行途中遮挡途经棋子）
    _paintMovingPiece(canvas);
  }

  /// 底板：圆角面板（描边由外层棋盘卡片负责）
  void _paintBase(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(geometry.cell * 0.18),
    );
    canvas.drawRRect(rrect, Paint()..color = surfaceColor);
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

  /// 河界文字：「楚河」「汉界」分列中线两侧；
  /// 棋盘 180° 旋转时两词位置对调（随盘旋转），文字本身保持正向
  void _paintRiverText(Canvas canvas) {
    final style = TextStyle(
      color: textSecondaryColor,
      fontSize: geometry.cell * 0.5,
      fontWeight: FontWeight.w600,
      letterSpacing: geometry.cell * 0.18,
    );
    final midY = geometry.margin + 4.5 * geometry.cell;
    final leftCol = geometry.flipped ? 6 : 2;
    final rightCol = geometry.flipped ? 2 : 6;
    _paintCenteredText(
        canvas, '楚河', Offset(geometry.margin + leftCol * geometry.cell, midY), style);
    _paintCenteredText(
        canvas, '漢界', Offset(geometry.margin + rightCol * geometry.cell, midY), style);
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
      // 边线交点只画盘内一侧：默认视角 col 0 是屏幕左缘画右侧；
      // 整盘 180° 旋转后左右对调，col 0 显示在屏幕右缘需改画左侧
      _drawMarkCorners(canvas, p, d1, d2, paint,
          left: geometry.flipped ? col < ChessBoard.cols - 1 : col > 0,
          right: geometry.flipped ? col > 0 : col < ChessBoard.cols - 1);
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

  /// 正在播放走子动画的走法；null 表示未在动画中：
  /// lastMove 为空、进度已到 1、或终点已无棋子（局面被再次变更——
  /// 如悔棋回退/重开新局，此时必须按原位绘制，防止终点棋子"隐身"）
  ChessMove? get _animatingMove {
    final move = lastMove;
    if (move == null || animProgress >= 1) return null;
    if (board.pieceAt(move.to) == null) return null;
    return move;
  }

  /// 全部棋子：米色圆面 + 红黑描边、内圈细线与居中汉字。
  /// 走子动画播放中时终点棋子跳过（由 [_paintMovingPiece] 画在插值位置）
  void _paintPieces(Canvas canvas) {
    final movingTo = _animatingMove?.to;
    for (var row = 0; row < ChessBoard.rows; row++) {
      for (var col = 0; col < ChessBoard.cols; col++) {
        if (movingTo == (col, row)) continue;
        final piece = board.pieceAt((col, row));
        if (piece == null) continue;
        _drawPiece(canvas, piece, geometry.posToOffset((col, row)));
      }
    }
  }

  /// 移动中的棋子：起点到终点按动画进度插值（easeOut 已由动画层施加），
  /// 阴影偏移加大模拟"提起"悬浮感；其余样式与静止棋子完全一致
  /// （等比绘制不缩放，任何画布尺寸下棋子都清晰不变形）。
  /// 被吃棋子在动画期间暂留绘制在终点位垫底
  void _paintMovingPiece(Canvas canvas) {
    final move = _animatingMove;
    if (move == null) return;
    final to = geometry.posToOffset(move.to);
    final captured = capturedPiece;
    if (captured != null) {
      _drawPiece(canvas, captured, to);
    }
    _drawPiece(
      canvas,
      board.pieceAt(move.to)!,
      Offset.lerp(geometry.posToOffset(move.from), to, animProgress)!,
      lifted: true,
    );
  }

  /// 绘制单枚棋子：阴影 + 米色圆面 + 色描边 + 内圈细线 + 居中汉字。
  /// [lifted] 为 true 时阴影更大更淡（走子动画中的悬浮感）
  void _drawPiece(
    Canvas canvas,
    ChessPiece piece,
    Offset center, {
    bool lifted = false,
  }) {
    final radius = geometry.cell * 0.45;
    final color = piece.color == ChessColor.red ? _redPiece : _blackPiece;

    // 轻微下移的阴影提升立体感（移动中的棋子阴影更大更淡）
    canvas.drawCircle(
      center + Offset(0, geometry.cell * (lifted ? 0.08 : 0.03)),
      radius,
      Paint()..color = lifted ? const Color(0x22000000) : const Color(0x33000000),
    );
    canvas.drawCircle(center, radius, Paint()..color = _pieceFace);
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
      oldDelegate.pendingMove != pendingMove ||
      oldDelegate.lastMove != lastMove ||
      oldDelegate.animProgress != animProgress;
}
