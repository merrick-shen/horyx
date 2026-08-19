import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 品牌主按钮
/// 全应用通用的强调操作按钮（如「开始 PK」「提交」）
/// outlined 为 true 时呈描边样式（次要操作，如「取消」）
/// onPressed 为 null 时呈禁用态（灰底、无阴影、不可点击）
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.outlined = false,
  });

  /// 按钮文字
  final String label;

  /// 点击回调；null 表示禁用
  final VoidCallback? onPressed;

  /// 可选的前置图标
  final IconData? icon;

  /// 是否描边样式（透明感弱化，用于与主按钮并排的次要操作）
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final palette = context.palette;

    // 描边态文字/图标用主题主文字色，实底态统一白色
    final contentColor =
        outlined ? palette.textPrimary : Colors.white;

    return DecoratedBox(
      decoration: BoxDecoration(
        // 实底：品牌纯色（禁用降级灰底）；描边：页面底色 + 描边
        color: !enabled
            ? palette.surfaceHover
            : outlined
                ? palette.scaffoldBg
                : palette.primary,
        borderRadius: BorderRadius.circular(14),
        border: outlined ? Border.all(color: palette.stroke) : null,
        boxShadow: enabled && !outlined
            ? [
                // 品牌色光晕投影，与游戏卡片悬停效果呼应
                BoxShadow(
                  color: palette.primary.withValues(alpha: 0.35),
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
                  Icon(icon, color: contentColor, size: 18),
                  const SizedBox(width: 8),
                ],
                // 品牌紫底上白字，深浅主题下对比度一致
                Text(
                  label,
                  style: TextStyle(
                    color: contentColor,
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
