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
/// 手势经几何换算转为格坐标后回调 [onCellTap]（棋盘外点击不回调）；
/// [checkFlashTrigger] 递增时在棋盘中央播放「将军」渐现渐隐提示
class ChessBoardView extends StatelessWidget {
  const ChessBoardView({
    super.key,
    required this.board,
    required this.turn,
    required this.selected,
    required this.legalTargets,
    required this.pendingMove,
    required this.checkFlashTrigger,
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

  /// 「将军」提示触发计数（页面层每检测到将军递增一次）
  final int checkFlashTrigger;

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
      child: Stack(
        children: [
          PageContent(
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
                            final pos = geometry.offsetToPos(
                              details.localPosition,
                            );
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
          // 「将军」提示覆盖层：不拦截触摸，仅做视觉提醒
          IgnorePointer(
            child: Center(
              child: _CheckFlashText(trigger: checkFlashTrigger),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「将军」渐现渐隐提示：[trigger] 每递增一次播放一遍动画
/// （快速放大淡入 -> 短暂停留 -> 淡出），黑底胶囊 + 白色大字保证醒目
class _CheckFlashText extends StatefulWidget {
  const _CheckFlashText({required this.trigger});

  final int trigger;

  @override
  State<_CheckFlashText> createState() => _CheckFlashTextState();
}

class _CheckFlashTextState extends State<_CheckFlashText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didUpdateWidget(covariant _CheckFlashText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && widget.trigger > 0) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        // 不透明度：0-15% 淡入，15%-75% 全显，75%-100% 淡出
        final opacity = t < 0.15
            ? t / 0.15
            : t > 0.75
            ? (1 - t) / 0.25
            : 1.0;
        // 淡入期从 1.4 倍缩到 1.0 倍，强化「冲出来」的醒目感
        final scale = t < 0.15 ? 1.4 - 0.4 * (t / 0.15) : 1.0;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          '将军',
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 10,
            shadows: [
              // 红色光晕 + 黑色锐影，双层阴影保证任何主题下都醒目
              Shadow(
                blurRadius: 18,
                color: ChessPieceColors.red.withValues(alpha: 0.9),
              ),
              const Shadow(blurRadius: 4, color: Colors.black),
            ],
          ),
        ),
      ),
    );
  }
}
