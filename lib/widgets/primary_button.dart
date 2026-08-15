import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 品牌渐变主按钮
/// 全应用通用的强调操作按钮（如「开始 PK」「提交」）
/// onPressed 为 null 时呈禁用态（灰底、无阴影、不可点击）
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  /// 按钮文字
  final String label;

  /// 点击回调；null 表示禁用
  final VoidCallback? onPressed;

  /// 可选的前置图标
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        // 禁用时降级为灰底，正常态使用品牌渐变
        gradient: enabled
            ? const LinearGradient(colors: AppColors.brandGradient)
            : null,
        color: enabled ? null : AppColors.surfaceHover,
        borderRadius: BorderRadius.circular(14),
        boxShadow: enabled
            ? [
                // 品牌色光晕投影，与游戏卡片悬停效果呼应
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
