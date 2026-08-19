import 'package:flutter/material.dart';

import '../../models/game_info.dart';
import '../../theme/app_theme.dart';

/// 游戏卡片组件
/// 桌面端悬停：卡片微放大 + 描边点亮 + 主题色光晕投影
/// 所有端：点击有水波纹反馈；接入游戏的卡片通过 onTap 跳转
class GameCard extends StatefulWidget {
  const GameCard({super.key, required this.game, this.onTap});

  final GameInfo game;

  /// 点击回调；null 时仅保留水波纹反馈（未接入游戏的占位卡片）
  final VoidCallback? onTap;

  @override
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final palette = context.palette;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: Material(
          color: _hovered ? palette.surfaceHover : palette.surfaceBg,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            // 未接入游戏的占位卡片保持水波纹反馈
            onTap: widget.onTap ?? () {},
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  width: 1.2,
                  // 悬停时描边切换为品牌主色，形成「点亮」效果
                  color: _hovered
                      ? palette.primary.withValues(alpha: 0.8)
                      : palette.stroke,
                ),
                boxShadow: [
                  if (_hovered)
                    BoxShadow(
                      color: palette.primary.withValues(alpha: 0.35),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 图标块：品牌主色，作为卡片视觉锚点
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: palette.primary,
                    ),
                    child: Icon(game.icon, color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    game.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    game.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                  const Spacer(),
                  // 底部播放按钮（悬停时点亮）
                  Align(
                    alignment: Alignment.centerRight,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // 浅色主题下悬停白底对比不足，改用品牌淡底
                        color: _hovered
                            ? palette.primary.withValues(alpha: 0.18)
                            : palette.stroke,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 20,
                        color: _hovered ? palette.primary : palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
