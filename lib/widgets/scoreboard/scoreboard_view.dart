import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../primary_button.dart';

/// 计分板 - 横屏对战计分视图（红蓝双方）
/// 两侧大数字为当前局小比分（点击对应侧加分），中央为局间大比分
/// 不含顶栏，全屏沉浸展示
class ScoreboardView extends StatelessWidget {
  const ScoreboardView({
    super.key,
    required this.bestOf,
    required this.redGames,
    required this.blueGames,
    required this.redScore,
    required this.blueScore,
    this.gameOver = false,
    this.winner,
    this.onRedTap,
    this.onBlueTap,
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

  /// 当前局已分出胜负（等待开始下一局）
  final bool gameOver;

  /// 整场胜方（'红方'/'蓝方'）；null 表示比赛进行中
  final String? winner;

  /// 点击红方计分区回调；null 时锁定不可点击
  final VoidCallback? onRedTap;

  /// 点击蓝方计分区回调；null 时锁定不可点击
  final VoidCallback? onBlueTap;

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
                      key: const Key('redPanel'),
                      color: redTeam,
                      name: '红方',
                      score: redScore,
                      onTap: onRedTap,
                    ),
                  ),
                  _GamesPanel(
                    bestOf: bestOf,
                    redGames: redGames,
                    blueGames: blueGames,
                    gameOver: gameOver,
                    winner: winner,
                  ),
                  Expanded(
                    child: _TeamPanel(
                      key: const Key('bluePanel'),
                      color: blueTeam,
                      name: '蓝方',
                      score: blueScore,
                      onTap: onBlueTap,
                    ),
                  ),
                ],
              ),
            ),
            // 底部操作条：撤销 + 退出计分
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: '撤销',
                      icon: Icons.undo_rounded,
                      outlined: true,
                      // 无计分记录时禁用
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
/// 点击面板为该方加 1 分（onTap 为 null 时锁定无反馈）
class _TeamPanel extends StatelessWidget {
  const _TeamPanel({
    super.key,
    required this.color,
    required this.name,
    required this.score,
    this.onTap,
  });

  /// 队伍标识色（红或蓝）
  final Color color;

  /// 队伍名
  final String name;

  /// 当前局得分
  final int score;

  /// 点击加分回调；null 表示锁定（终局）
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: InkWell(
        onTap: onTap,
        // 纯色底上用白色半透明水波纹，与白字视觉一致
        splashColor: Colors.white.withValues(alpha: 0.15),
        highlightColor: Colors.white.withValues(alpha: 0.1),
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
    required this.gameOver,
    required this.winner,
  });

  final int bestOf;
  final int redGames;
  final int blueGames;

  /// 当前局已分出胜负
  final bool gameOver;

  /// 整场胜方；null 表示比赛进行中
  final String? winner;

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
            // 局数提示：终局/本局结束时替换为对应状态文案
            Text(
              winner != null
                  ? '比赛结束'
                  : gameOver
                      ? '本局结束'
                      : '第 ${redGames + blueGames + 1} 局',
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
