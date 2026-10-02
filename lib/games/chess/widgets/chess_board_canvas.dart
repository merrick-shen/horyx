import 'package:flutter/material.dart';

import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/models/chess_piece.dart';
import 'package:horyx/games/chess/widgets/chess_board_geometry.dart';
import 'package:horyx/games/chess/widgets/chess_board_painter.dart';
import 'package:horyx/shared/theme/app_theme.dart';

/// 象棋棋盘画布：棋盘按可用空间等比缩放 + 点击手势命中
/// （本地对局视图与联机对局视图共用）；
/// 几何换算与绘制来自 [ChessBoardGeometry]/[ChessBoardPainter]，
/// 点击经换算吸附到最近交点后回调 [onCellTap]（棋盘外框以外点击不回调）。
/// 走子过渡动画：[lastMove] 变化（以 [lastMoveSeq] 判定新走法）时内部
/// AnimationController 驱动棋子从起点滑向终点——纯渲染层修饰，逻辑局面
/// 在动画开始前已由页面走完 applyMove，动画不阻塞不拦截任何交互
class ChessBoardCanvas extends StatefulWidget {
  const ChessBoardCanvas({
    super.key,
    required this.board,
    required this.selected,
    required this.legalTargets,
    required this.pendingMove,
    required this.onCellTap,
    this.lastMove,
    this.capturedPiece,
    this.lastMoveSeq = 0,
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

  /// 最近一步走法（走子动画用）；null 表示无动画（悔棋/重开/恢复存档时由
  /// 页面清空——回退类局面变化不做动画，回退语义与前进滑行观感不符）
  final ChessMove? lastMove;

  /// 最近一步被吃的棋子（动画期间暂留显示在终点位，见
  /// [ChessBoardPainter.capturedPiece]）
  final ChessPiece? capturedPiece;

  /// 最近一步的触发序号（页面侧单调递增计数）：与 [lastMove] 配合判定
  /// "新走法"——相同起终点坐标的走法先后发生时走法记录相等，
  /// 仅靠走法判等会漏触发，序号保证每次走子动画可靠重放
  final int lastMoveSeq;

  /// 是否整盘旋转 180°（联机执黑方为 true：己方棋子显示在屏幕下方）
  final bool flipped;

  @override
  State<ChessBoardCanvas> createState() => _ChessBoardCanvasState();
}

class _ChessBoardCanvasState extends State<ChessBoardCanvas>
    with SingleTickerProviderStateMixin {
  /// 走子滑动动画：短促 easeOut（先快后缓），接近真实落子的节奏
  late final AnimationController _moveAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );

  @override
  void didUpdateWidget(ChessBoardCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 新走法到来：从头播放滑动动画。上一动画未结束时直接重播——
    // 终点棋子瞬间就位后从新起点滑出（逻辑局面始终领先于动画，
    // 连续快速走子也不会出现两枚棋子同时滑行的错乱）
    if (widget.lastMove != null &&
        widget.lastMoveSeq != oldWidget.lastMoveSeq) {
      _moveAnim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _moveAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    // 棋盘卡片：圆角与描边对齐五子棋棋盘卡片（Radii.card + 主题描边色）
    return Center(
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: palette.surfaceBg,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: palette.stroke),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.control),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final geometry = ChessBoardGeometry.forSize(
                constraints.biggest,
                flipped: widget.flipped,
              );
              return GestureDetector(
                onTapUp: (details) {
                  // 点击吸附到最近线路交点，棋盘外框以外不响应
                  final pos = geometry.offsetToPos(details.localPosition);
                  if (pos != null) widget.onCellTap(pos);
                },
                // AnimatedBuilder 只驱动棋盘重绘：动画逐帧以当前进度重建
                // painter（easeOut 缓出直接按值取曲线；几何在闭包内随布局
                // 实时换算，画布尺寸变化中途动画也按最新尺寸正确呈现）
                child: AnimatedBuilder(
                  animation: _moveAnim,
                  builder: (context, _) => CustomPaint(
                    size: geometry.boardSize,
                    painter: ChessBoardPainter(
                      board: widget.board,
                      geometry: geometry,
                      surfaceColor: palette.surfaceBg,
                      strokeColor: palette.stroke,
                      textSecondaryColor: palette.textSecondary,
                      primaryColor: palette.primary,
                      selected: widget.selected,
                      legalTargets: widget.legalTargets,
                      pendingMove: widget.pendingMove,
                      lastMove: widget.lastMove,
                      capturedPiece: widget.capturedPiece,
                      animProgress:
                          Curves.easeOut.transform(_moveAnim.value),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
