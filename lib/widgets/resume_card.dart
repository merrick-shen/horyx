import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 继续上次对局/计分入口卡片
/// 各游戏设置页通用的恢复入口：品牌色淡底 + 播放图标 + 进度摘要，
/// 点击后由页面从存档恢复对局
class ResumeCard extends StatelessWidget {
  const ResumeCard({
    super.key,
    required this.summary,
    this.title = '继续上次对局',
    this.onTap,
  });

  /// 卡片标题；计分器等非对局场景可覆盖（如「继续上次计分」）
  final String title;

  /// 进度摘要（如「9×9 对局 · 已下 5 手」），由各游戏按存档组装
  final String summary;

  /// 点击卡片回调（触发存档恢复）
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // 品牌色淡底 + 描边，与普通卡片区分，突出「可继续」
          color: palette.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: palette.primary.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.play_circle_fill_rounded,
              color: palette.primary,
              size: 34,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    summary,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: palette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
