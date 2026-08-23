import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 弹窗底部操作按钮：默认描边样式，[filled] 为 true 时实底主按钮样式
/// 实底默认品牌色（带品牌色光晕）；传入 [fillColor] 可自定义实底色
/// （如颜色选择器的「确定」用当前所选色，此时不加光晕避免浅色光晕刺眼）
/// 确认弹窗、终局弹窗、颜色选择器共用
class DialogActionButton extends StatelessWidget {
  const DialogActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.fillColor,
  });

  /// 按钮文案
  final String label;

  /// 点击回调
  final VoidCallback onPressed;

  /// 是否实底主按钮样式
  final bool filled;

  /// 实底自定义颜色（默认 null 即品牌色）
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final background = fillColor ?? palette.primary;

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? background : palette.scaffoldBg,
          borderRadius: BorderRadius.circular(13),
          border: filled ? null : Border.all(color: palette.stroke),
          // 品牌色实底带光晕强调主操作；自定义颜色（如当前所选色）不加，
          // 浅色/高亮度的光晕视觉效果差
          boxShadow: filled && fillColor == null
              ? [
                  BoxShadow(
                    color: palette.primary.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: filled ? Colors.white : palette.textPrimary,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
