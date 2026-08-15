import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../primary_button.dart';

/// 计分板 - 横屏对战计分视图（红蓝双方）
/// 两侧大数字为当前局小比分（点击加分，交互待开发），中央为局间大比分
/// 不含顶栏，全屏沉浸展示
class ScoreboardView extends StatelessWidget {
  const ScoreboardView({
    super.key,
    required this.bestOf,
    required this.redGames,
    required this.blueGames,
    required this.redScore,
    required this.blueScore,
    this.onUndo,
    required this.onExit,
  });

  /// 赛制（BO 几，先赢多数局获胜）
  final int bestOf;

  /// 红方已获胜局数（大比分）
  final int redGames;

  /// 蓝方已获胜局数（大比分）
  final int blueGames;

  /// 红方当前局得分（小比分）
  final int redScore;

  /// 蓝方当前局得分（小比分）
  final int blueScore;

  /// 撤销上一次计分；null 呈禁用态
  final VoidCallback? onUndo;

  /// 退出计分回到设置视图
  final VoidCallback onExit;

  /// 红蓝为体育计分惯例固定色，不随主题/品牌强调色变化
  static const Color redTeam = Color(0xFFE5484D);
  static const Color blueTeam = Color(0xFF3E63DD);

  @override
  Widget build(BuildContext context) {
    // 横屏纵向空间紧凑：计分区占满剩余高度，底部固定操作条
    return Scaffold(
      // 横屏左右刘海/挖孔通过 SafeArea 避让
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _TeamPanel(
                      color: redTeam,
                      name: '红方',
                      score: redScore,
                    ),
                  ),
                  _GamesPanel(
                    bestOf: bestOf,
                    redGames: redGames,
                    blueGames: blueGames,
                  ),
                  Expanded(
                    child: _TeamPanel(
                      color: blueTeam,
                      name: '蓝方',
                      score: blueScore,
                    ),
                  ),
                ],
              ),
            ),
            // 底部操作条：撤销（禁用占位）+ 退出计分
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: '撤销',
                      icon: Icons.undo_rounded,
                      outlined: true,
                      onPressed: onUndo,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      label: '退出计分',
                      icon: Icons.logout_rounded,
                      outlined: true,
                      onPressed: onExit,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单侧队伍面板：固定红/蓝纯色底 + 白字队伍名 + 当前局大数字
class _TeamPanel extends StatelessWidget {
  const _TeamPanel({
    required this.color,
    required this.name,
    required this.score,
  });

  /// 队伍标识色（红或蓝）
  final Color color;

  /// 队伍名
  final String name;

  /// 当前局得分
  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: TextStyle(
                // 半透明白做次级层次，不引入额外色相
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 4),
            // FittedBox 防止小尺寸横屏下数字溢出
            FittedBox(
              child: Text(
                '$score',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 92,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 中央大比分牌：局分（红 X : X 蓝）+ 赛制与当前局数提示
class _GamesPanel extends StatelessWidget {
  const _GamesPanel({
    required this.bestOf,
    required this.redGames,
    required this.blueGames,
  });

  final int bestOf;
  final int redGames;
  final int blueGames;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: 150,
      // 左右描边与红蓝区域分隔
      decoration: BoxDecoration(
        color: palette.surfaceBg,
        border: Border.symmetric(
          vertical: BorderSide(color: palette.stroke),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 赛制提示
            Text(
              'BO$bestOf',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '大比分',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            // 局分红:蓝，数字沿用双方标识色便于对应
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$redGames',
                  style: const TextStyle(
                    color: ScoreboardView.redTeam,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    ':',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$blueGames',
                  style: const TextStyle(
                    color: ScoreboardView.blueTeam,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 当前局数：已结束局数 + 1
            Text(
              '第 ${redGames + blueGames + 1} 局',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
