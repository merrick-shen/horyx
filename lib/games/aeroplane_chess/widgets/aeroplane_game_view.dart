import 'package:flutter/material.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';
import 'package:horyx/games/aeroplane_chess/widgets/aeroplane_board_view.dart';
import 'package:horyx/games/aeroplane_chess/widgets/aeroplane_dice.dart';
import 'package:horyx/shared/widgets/confirm_move_row.dart';
import 'package:horyx/shared/widgets/page_content.dart';
import 'package:horyx/shared/widgets/primary_button.dart';
import 'package:horyx/shared/widgets/turn_card.dart';

/// 飞行棋 - 本地对局视图：回合卡 + 棋盘（含棋子层）+ 骰面 + 走子确认 +
/// 掷骰按钮。交互链路：底部按钮掷骰 -> 点可动棋子选中 -> 确认行
/// 「取消/下棋」执行走法；动效反馈自下一阶段接入
class AeroplaneGameView extends StatelessWidget {
  const AeroplaneGameView({
    super.key,
    required this.state,
    required this.dice,
    required this.canRoll,
    required this.movable,
    required this.selected,
    required this.onRoll,
    required this.onPlaneTap,
    required this.onCancelMove,
    required this.onConfirmMove,
    required this.onRestart,
  });

  /// 对局状态
  final AeroplaneGameState state;

  /// 展示中的骰点（null = 本局尚未掷骰，骰面隐藏占位）
  final int? dice;

  /// 掷骰按钮可用（等待掷骰阶段）
  final bool canRoll;

  /// 可动棋子（高亮 + 可点击）
  final Set<(AeroplaneColor, int)> movable;

  /// 选中的棋子
  final (AeroplaneColor, int)? selected;

  /// 点击「掷骰子」回调
  final VoidCallback onRoll;

  /// 点击可动棋子回调
  final void Function(AeroplaneColor color, int planeId) onPlaneTap;

  /// 点击「取消」回调：清除选中
  final VoidCallback onCancelMove;

  /// 点击「下棋」回调：执行走法
  final VoidCallback onConfirmMove;

  /// 终局后点击「再来一局」回调
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final over = state.gameOver;
    final turnColor = over ? state.winner! : state.currentPlayer;
    final turnPlayer = state.players
        .firstWhere((p) => p.color == turnColor);
    return SizedBox.expand(
      child: PageContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 回合卡：对局中提示当前行动方，终局切换为胜方展示
            TurnCard(
              icon: over
                  ? Icons.emoji_events_rounded
                  : Icons.flight_takeoff_rounded,
              subtitle: over ? '对局结束' : '当前回合',
              title: over
                  ? '${turnColor.label}方胜利'
                  : '${turnPlayer.name} · ${turnColor.label}方',
              titleKey: ValueKey(turnColor),
            ),
            const SizedBox(height: 12),
            // 棋盘独占剩余高度（贴顶满宽）：骰子若与之均分弹性空间，
            // 会把棋盘压小、两侧出现超出页边距的留白
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: AeroplaneBoardView(
                  planes: state.planes,
                  movable: movable,
                  selected: selected,
                  onPlaneTap: onPlaneTap,
                ),
              ),
            ),
            SizedBox(
              height: 120,
              child: Center(
                child: dice == null
                    ? const SizedBox.shrink()
                    : AeroplaneDice(value: dice!),
              ),
            ),
            const SizedBox(height: 12),
            ConfirmMoveRow(
              visible: selected != null,
              onCancelMove: onCancelMove,
              onConfirmMove: onConfirmMove,
            ),
            const SizedBox(height: 12),
            _buildAction(),
          ],
        ),
      ),
    );
  }

  Widget _buildAction() {
    if (state.gameOver) {
      return PrimaryButton(
        label: '再来一局',
        icon: Icons.refresh_rounded,
        onPressed: onRestart,
      );
    }
    return PrimaryButton(
      label: '掷骰子',
      icon: Icons.casino_rounded,
      onPressed: canRoll ? onRoll : null,
    );
  }
}
