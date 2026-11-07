import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';
import 'package:horyx/games/aeroplane_chess/widgets/aeroplane_board_view.dart';
import 'package:horyx/games/aeroplane_chess/widgets/aeroplane_dice.dart';
import 'package:horyx/shared/widgets/confirm_move_row.dart';
import 'package:horyx/shared/widgets/hint_overlay.dart';
import 'package:horyx/shared/widgets/page_content.dart';
import 'package:horyx/shared/widgets/primary_button.dart';
import 'package:horyx/shared/widgets/turn_card.dart';

/// 飞行棋对局视图（本地与联机对局页共用）：回合卡 + 棋盘（含棋子层与
/// 走子动画）+ 骰面（滚动翻动）+ 走子确认行 + 底部按钮 + 覆盖层渐现
/// 渐隐提示（不拦截触摸）。默认回合卡与底部按钮为本地口径（当前回合 /
/// 再来一局 / 掷骰子），联机页以 [turnTitle]/[turnSubtitle]/[actions]
/// 注入差异（对方名字标题、退出对局按钮）
class AeroplaneGameView extends StatelessWidget {
  const AeroplaneGameView({
    super.key,
    required this.state,
    required this.dice,
    required this.rolling,
    required this.movable,
    required this.selected,
    required this.moveAnim,
    required this.onPlaneTap,
    required this.onCancelMove,
    required this.onConfirmMove,
    required this.hintTrigger,
    required this.hintText,
    required this.hintColor,
    this.turnTitle,
    this.turnSubtitle,
    this.actions,
    this.canRoll = false,
    this.onRoll,
    this.onRestart,
  });

  /// 对局状态
  final AeroplaneGameState state;

  /// 展示中的骰点（null = 本局尚未掷骰，骰面隐藏占位）
  final int? dice;

  /// 骰子滚动动画中（骰面快速翻动 + 轻微放大）
  final bool rolling;

  /// 可动棋子（高亮 + 可点击）
  final Set<(AeroplaneColor, int)> movable;

  /// 选中的棋子
  final (AeroplaneColor, int)? selected;

  /// 走子/被撞飞行动画的移动棋子坐标流
  final ValueListenable<List<(AeroplaneColor, int, Point<double>)>>? moveAnim;

  /// 点击可动棋子回调
  final void Function(AeroplaneColor color, int planeId) onPlaneTap;

  /// 点击「取消」回调：清除选中
  final VoidCallback onCancelMove;

  /// 点击「下棋」回调：执行走法
  final VoidCallback onConfirmMove;

  /// 覆盖层提示（触发序号 / 文本 / 语义色；文本为空不显示）
  final int hintTrigger;
  final String hintText;
  final Color hintColor;

  /// 回合卡标题覆盖（联机按对方名字组装）；null 按本地口径：
  /// 终局「X方胜利」，否则「玩家 · X方」
  final String? turnTitle;

  /// 回合卡副标题覆盖（联机按行动进度组装）；null 按本地口径：
  /// 终局「对局结束」，否则「当前回合」
  final String? turnSubtitle;

  /// 底部按钮覆盖（联机为退出/掷骰组合）；null 按本地口径：
  /// 终局「再来一局」，否则「掷骰子」（依赖 [canRoll]/[onRoll]/[onRestart]）
  final Widget? actions;

  /// 掷骰按钮可用（等待掷骰阶段；[actions] 覆盖时不参与）
  final bool canRoll;

  /// 点击「掷骰子」回调（[actions] 覆盖时不参与）
  final VoidCallback? onRoll;

  /// 终局后点击「再来一局」回调（[actions] 覆盖时不参与）
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    final over = state.gameOver;
    final turnColor = over ? state.winner! : state.currentPlayer;
    final title = turnTitle ??
        (over
            ? '${turnColor.label}方胜利'
            : '${state.players.firstWhere((p) => p.color == turnColor).name} · ${turnColor.label}方');
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
                  subtitle: turnSubtitle ?? (over ? '对局结束' : '当前回合'),
                  title: title,
                  titleKey: ValueKey(title),
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
                AeroplaneDiceSlot(dice: dice, rolling: rolling),
                const SizedBox(height: 12),
                ConfirmMoveRow(
                  visible: selected != null,
                  onCancelMove: onCancelMove,
                  onConfirmMove: onConfirmMove,
                ),
                const SizedBox(height: 12),
                actions ?? _buildAction(),
              ],
            ),
          ),
          // 对局反馈提示覆盖层：不拦截触摸，仅做视觉提醒
          HintOverlay(
            trigger: hintTrigger,
            text: hintText,
            accentColor: hintColor,
            fontSize: 30,
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
