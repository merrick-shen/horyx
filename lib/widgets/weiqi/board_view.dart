import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../common/confirm_move_row.dart';
import '../common/primary_button.dart';
import '../common/stone_board.dart';
import '../common/stone_turn_card.dart';

/// 围棋 - 对局视图：执子提示 + 提子数面板 + 棋盘 + 操作按钮
class WeiqiBoardView extends StatelessWidget {
  const WeiqiBoardView({
    super.key,
    required this.boardSize,
    required this.stones,
    required this.pending,
    required this.blackToMove,
    required this.gameOver,
    required this.winner,
    required this.blackCaptures,
    required this.whiteCaptures,
    required this.canUndo,
    required this.onCellTap,
    required this.onCancelMove,
    required this.onConfirmMove,
    required this.onUndo,
    required this.onPass,
    required this.onRestart,
  });

  /// 棋盘路数
  final int boardSize;

  /// 当前棋子集合（提子后的实时盘面）
  final List<Stone> stones;

  /// 预选落子位置；null 表示无预选
  final (int, int)? pending;

  /// 当前执黑方（终局后无意义）
  final bool blackToMove;

  /// 是否终局
  final bool gameOver;

  /// 胜方（'黑方'/'白方'）；未终局为 null
  final String? winner;

  /// 黑方提子数
  final int blackCaptures;

  /// 白方提子数
  final int whiteCaptures;

  /// 是否有着手可悔
  final bool canUndo;

  /// 点击棋盘交叉点回调
  final void Function(int col, int row) onCellTap;

  /// 点击「取消」回调：清除落子预选
  final VoidCallback onCancelMove;

  /// 点击「下棋」回调：确认落子
  final VoidCallback onConfirmMove;

  /// 点击「悔棋」回调
  final VoidCallback onUndo;

  /// 点击「虚手」回调：停一手轮换执子
  final VoidCallback onPass;

  /// 点击「再来一局」回调（终局后）
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    // 落子确认按钮仅在棋盘上有预选棋子时出现（终局后不会产生预选）
    final hasPending = pending != null;

    return SizedBox.expand(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 对局中提示执子方，终局显示胜方（图标颜色对应棋子）
                StoneTurnCard(
                  isOver: gameOver,
                  blackToMove: blackToMove,
                  winner: winner,
                  subtitle: '当前执子',
                ),
                const SizedBox(height: 12),
                // 双方提子数面板（提子生效后实时更新）
                Row(
                  children: [
                    Expanded(
                      child: _CaptureCard(
                        label: '黑方提子',
                        count: blackCaptures,
                        stoneColor: StoneBoard.blackStone,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _CaptureCard(
                        label: '白方提子',
                        count: whiteCaptures,
                        stoneColor: StoneBoard.whiteStone,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 棋盘占据剩余空间，正方形自适应宽高较小者
                Expanded(
                  child: Center(
                    child: StoneBoard(
                      size: boardSize,
                      stones: stones,
                      pending: pending == null
                          ? null
                          : (pending!.$1, pending!.$2, blackToMove),
                      onCellTap: onCellTap,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ConfirmMoveRow(
                  visible: hasPending,
                  onCancelMove: onCancelMove,
                  onConfirmMove: onConfirmMove,
                ),
                const SizedBox(height: 12),
                // 对局操作：虚手（停一手）+ 悔棋；终局后换为再来一局
                gameOver
                    ? PrimaryButton(
                        label: '再来一局',
                        icon: Icons.refresh_rounded,
                        onPressed: onRestart,
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: PrimaryButton(
                              label: '虚手',
                              icon: Icons.hourglass_bottom_rounded,
                              outlined: true,
                              onPressed: onPass,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: PrimaryButton(
                              label: '悔棋',
                              icon: Icons.undo_rounded,
                              onPressed: canUndo ? onUndo : null,
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 提子数卡片：棋子色圆点 + 方名 + 提子数
class _CaptureCard extends StatelessWidget {
  const _CaptureCard({
    required this.label,
    required this.count,
    required this.stoneColor,
  });

  /// 方名（如「黑方提子」，同时作为数字 Key 供测试定位）
  final String label;

  /// 提子数
  final int count;

  /// 对应棋子颜色（圆点展示）
  final Color stoneColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: palette.surfaceBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.stroke),
      ),
      child: Row(
        children: [
          // 棋子圆点：描边保证深浅主题下轮廓清晰（与棋盘棋子一致）
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: stoneColor,
              border: Border.all(color: palette.stroke),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: palette.textSecondary, fontSize: 12.5),
          ),
          const Spacer(),
          Text(
            '$count',
            key: ValueKey(label),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
