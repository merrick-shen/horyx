import 'package:flutter/material.dart';

import 'package:horyx/games/chess/models/chess_board.dart';

/// 棋盘几何换算：逻辑格坐标 ↔ 屏幕像素，绘制（painter）与手势命中（canvas）
/// 共用同一套换算
/// 屏幕方向约定：默认 row 0（红方底线）画在底部（双人同屏的红方视角）；
/// [flipped] 为 true 时整盘旋转 180°（中心对称：row 9 画在底部且左右对调），
/// 联机对局中执黑方用它让自己的棋子显示在下方、棋子相对位置与真实
/// 对面视角一致（棋子汉字由 TextPainter 正常绘制，朝向不随旋转）
class ChessBoardGeometry {
  ChessBoardGeometry._({
    required this.cell,
    required this.margin,
    required this.flipped,
  }) : boardSize = Size(
          (ChessBoard.cols - 1) * cell + margin * 2,
          (ChessBoard.rows - 1) * cell + margin * 2,
        );

  /// 格距（相邻线路间距，棋盘等比缩放的最小单位）
  final double cell;

  /// 线路区距棋盘边缘的留白（容纳棋子半径与外框）
  final double margin;

  /// 是否旋转 180°（黑方视角：黑方底线画在屏幕底部且左右对调）
  final bool flipped;

  /// 棋盘整体尺寸
  final Size boardSize;

  /// 线路区距边缘的留白占格距比例（比例化保证任意尺寸下观感一致）
  static const double _marginRatio = 0.55;

  /// 按可用空间计算几何：
  /// 棋盘总宽 = (cols-1)*cell + 2*margin = 9.1*cell，总高 = 10.1*cell，
  /// cell 取宽高约束下较小者，保证棋盘完整可见且等比缩放
  factory ChessBoardGeometry.forSize(Size available, {bool flipped = false}) {
    final w = available.width / (ChessBoard.cols - 1 + _marginRatio * 2);
    final h = available.height / (ChessBoard.rows - 1 + _marginRatio * 2);
    final cell = w < h ? w : h;
    return ChessBoardGeometry._(
      cell: cell,
      margin: cell * _marginRatio,
      flipped: flipped,
    );
  }

  /// 格坐标 → 屏幕中心点（默认 row 0 在屏幕底部；
  /// 翻转时整盘 180° 旋转：row 9 在底部、col 8 在左侧）
  Offset posToOffset(ChessPos pos) {
    final (col, row) = pos;
    final x = flipped ? (ChessBoard.cols - 1 - col) * cell : col * cell;
    final y = flipped ? row * cell : (ChessBoard.rows - 1 - row) * cell;
    return Offset(margin + x, margin + y);
  }

  /// 屏幕点 → 最近线路交点（与 [posToOffset] 互逆）。
  /// 命中为吸附式：横/纵方向距最近交点均不超过半格即吸附命中——
  /// 整个棋盘面（含留白外框以内）的点击都会命中最近交点，利于
  /// 粗手指点选边线棋子，属有意设计；外框以外的点击返回 null
  ChessPos? offsetToPos(Offset o) {
    var col = ((o.dx - margin) / cell).round();
    final rowFromEdge = ((o.dy - margin) / cell).round();
    if (flipped) col = ChessBoard.cols - 1 - col;
    final row = flipped ? rowFromEdge : ChessBoard.rows - 1 - rowFromEdge;
    if (col < 0 || col >= ChessBoard.cols || row < 0 || row >= ChessBoard.rows) {
      return null;
    }
    return (col, row);
  }
}
