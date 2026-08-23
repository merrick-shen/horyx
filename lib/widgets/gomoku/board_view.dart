import 'package:flutter/material.dart';

import '../common/confirm_move_row.dart';
import '../common/primary_button.dart';
import '../common/stone_board.dart';
import '../common/stone_turn_card.dart';

/// 五子棋 - 对局视图：当前执子提示 + 棋盘 + 操作按钮
class GomokuBoardView extends StatelessWidget {
  const GomokuBoardView({
    super.key,
    required this.boardSize,
    required this.moves,
    required this.pending,
    required this.winner,
    required this.onCellTap,
    required this.onCancelMove,
    required this.onConfirmMove,
    required this.onUndo,
    required this.onRestart,
  });

  /// 棋盘路数
  final int boardSize;

  /// 已确认落子序列
  final List<(int, int)> moves;

  /// 预选落子位置；null 表示无预选
  final (int, int)? pending;

  /// 胜方；null 表示对局进行中
  final String? winner;

  /// 点击棋盘交叉点回调
  final void Function(int col, int row) onCellTap;

  /// 点击「取消」回调：清除落子预选
  final VoidCallback onCancelMove;

  /// 点击「下棋」回调：确认落子
  final VoidCallback onConfirmMove;

  /// 点击「悔棋」回调
  final VoidCallback onUndo;

  /// 终局后点击「再来一局」回调：清盘重开
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    // 落子确认按钮仅在棋盘上有预选棋子时出现
    final hasPending = pending != null;
    // 终局后无预选、无子可悔
    final isOver = winner != null;
    final blackTurn = moves.length.isEven;

    return SizedBox.expand(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 对局中提示执子方（图标颜色对应棋子）；终局提示胜方
                StoneTurnCard(
                  isOver: isOver,
                  blackToMove: blackTurn,
                  winner: winner,
                  subtitle: '当前执子',
                ),
                const SizedBox(height: 16),
                // 棋盘占据剩余空间，正方形自适应宽高较小者
                Expanded(
                  child: Center(
                    // 五子棋无提子，落子序列奇偶即可推导颜色（先手黑）
                    // 转换为显式颜色棋子集合供通用棋盘组件绘制
                    child: StoneBoard(
                      size: boardSize,
                      stones: [
                        for (int i = 0; i < moves.length; i++)
                          (moves[i].$1, moves[i].$2, i.isEven),
                      ],
                      pending: pending == null
                          ? null
                          : (
                              pending!.$1,
                              pending!.$2,
                              moves.length.isEven,
                            ),
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
                if (isOver)
                  // 终局：悔棋替换为再来一局，方便查看棋型后重开
                  PrimaryButton(
                    label: '再来一局',
                    icon: Icons.refresh_rounded,
                    onPressed: onRestart,
                  )
                else
                  // 对局中：无子可悔时按钮禁用（灰底不可点击）
                  PrimaryButton(
                    label: '悔棋',
                    icon: Icons.undo_rounded,
                    onPressed: moves.isEmpty ? null : onUndo,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
