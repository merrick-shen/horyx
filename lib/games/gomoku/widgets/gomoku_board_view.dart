import 'package:flutter/material.dart';

import 'package:horyx/games/gomoku/widgets/gomoku_game_layout.dart';
import 'package:horyx/shared/widgets/primary_button.dart';

/// 五子棋 - 本地对局视图：执子提示 + 棋盘 + 落子确认 + 悔棋/再来一局。
/// 布局骨架（执子卡 + 棋盘 + 确认行 + 按钮插槽）见 [GomokuGameLayout]，
/// 本视图只组装本地专属的执子卡副标题与底部按钮集
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
    final isOver = winner != null;
    return GomokuGameLayout(
      boardSize: boardSize,
      moves: moves,
      pending: pending,
      winner: winner,
      turnSubtitle: '当前执子',
      onCellTap: onCellTap,
      onCancelMove: onCancelMove,
      onConfirmMove: onConfirmMove,
      actions: isOver
          ? // 终局：悔棋替换为再来一局，方便查看棋型后重开
          PrimaryButton(
              label: '再来一局',
              icon: Icons.refresh_rounded,
              onPressed: onRestart,
            )
          : // 对局中：无子可悔时按钮禁用（灰底不可点击）
          PrimaryButton(
              label: '悔棋',
              icon: Icons.undo_rounded,
              onPressed: moves.isEmpty ? null : onUndo,
            ),
    );
  }
}
