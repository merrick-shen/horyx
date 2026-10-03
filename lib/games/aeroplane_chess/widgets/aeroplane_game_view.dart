import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';
import 'package:horyx/games/aeroplane_chess/widgets/aeroplane_board_view.dart';
import 'package:horyx/games/aeroplane_chess/widgets/aeroplane_dice.dart';
import 'package:horyx/shared/widgets/confirm_move_row.dart';
import 'package:horyx/shared/widgets/flash_hint.dart';
import 'package:horyx/shared/widgets/page_content.dart';
import 'package:horyx/shared/widgets/primary_button.dart';
import 'package:horyx/shared/widgets/turn_card.dart';

/// 飞行棋 - 本地对局视图：回合卡 + 棋盘（含棋子层与走子动画）+ 骰面
/// （滚动翻动）+ 走子确认 + 掷骰按钮；撞子/飞越/惩罚等反馈走覆盖层
/// 渐现渐隐提示（不拦截触摸）
class AeroplaneGameView extends StatelessWidget {
  const AeroplaneGameView({
    super.key,
    required this.state,
    required this.dice,
    required this.rolling,
    required this.canRoll,
    required this.movable,
    required this.selected,
    required this.moveAnim,
    required this.onRoll,
    required this.onPlaneTap,
    required this.onCancelMove,
    required this.onConfirmMove,
    required this.onRestart,
    required this.hintTrigger,
    required this.hintText,
    required this.hintColor,
  });

  /// 对局状态
  final AeroplaneGameState state;

  /// 展示中的骰点（null = 本局尚未掷骰，骰面隐藏占位）
  final int? dice;

  /// 骰子滚动动画中（骰面快速翻动 + 轻微放大）
  final bool rolling;

  /// 掷骰按钮可用（等待掷骰阶段）
  final bool canRoll;

  /// 可动棋子（高亮 + 可点击）
  final Set<(AeroplaneColor, int)> movable;

  /// 选中的棋子
  final (AeroplaneColor, int)? selected;

  /// 走子/被撞飞行动画的移动棋子坐标流
  final ValueListenable<List<(AeroplaneColor, int, Point<double>)>>? moveAnim;

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

  /// 覆盖层提示（触发序号 / 文本 / 语义色；文本为空不显示）
  final int hintTrigger;
  final String hintText;
  final Color hintColor;

  @override
  Widget build(BuildContext context) {
    final over = state.gameOver;
    final turnColor = over ? state.winner! : state.currentPlayer;
    final turnPlayer = state.players.firstWhere((p) => p.color == turnColor);
    return SizedBox.expand(
      child: Stack(
        children: [
          PageContent(
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
                      moveAnim: moveAnim,
                      onPlaneTap: onPlaneTap,
                    ),
                  ),
                ),
                SizedBox(
                  height: 120,
                  child: Center(
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 80),
                      scale: rolling ? 1.08 : 1.0,
                      child: dice == null
                          ? const SizedBox.shrink()
                          : AeroplaneDice(value: dice!),
                    ),
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
          // 对局反馈提示覆盖层：不拦截触摸，仅做视觉提醒
          if (hintText.isNotEmpty)
            IgnorePointer(
              child: Center(
                child: FlashHint(
                  trigger: hintTrigger,
                  text: hintText,
                  accentColor: hintColor,
                  fontSize: 30,
                ),
              ),
            ),
        ],
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
