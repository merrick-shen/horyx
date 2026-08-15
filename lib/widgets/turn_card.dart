import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 通用回合信息卡：品牌色强调卡片，展示当前回合关键信息
/// （如单词PK「当前输入者·玩家N」、五子棋「当前执子·黑方」）
/// 标题文字带 key 时启用切换动画（玩家/执子方轮换的视觉提示）
class TurnCard extends StatelessWidget {
  const TurnCard({
    super.key,
    required this.icon,
    required this.subtitle,
    required this.title,
    this.titleKey,
  });

  /// 左侧图标
  final IconData icon;

  /// 小标题（说明信息含义）
  final String subtitle;

  /// 主标题（当前回合方）
  final String title;

  /// 主标题 key；变化时触发淡入淡出切换动画
  final Key? titleKey;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.primary,
        borderRadius: BorderRadius.circular(20),
        // 品牌色光晕强调「当前回合」
        boxShadow: [
          BoxShadow(
            color: palette.primary.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 半透明白色小字，叠在品牌色底上仍清晰
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              // 回合方切换时淡入淡出，强化轮换感知
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  title,
                  key: titleKey,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
