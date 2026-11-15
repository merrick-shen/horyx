import 'package:flutter/material.dart';

import 'package:horyx/shared/theme/app_theme.dart';

/// 弹窗底部操作按钮：默认描边样式，[filled] 为 true 时实底主按钮样式
/// 实底默认主题色；传入 [fillColor] 可自定义实底色
/// （如颜色选择器的「确定」用当前所选色）
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

  /// 实底自定义颜色（默认 null 即主题色）
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final background = fillColor ?? palette.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: filled ? background : palette.scaffoldBg,
        borderRadius: BorderRadius.circular(Radii.control),
        border: filled ? null : Border.all(color: palette.stroke),
      ),
      // Material+InkWell 标准写法（同 PrimaryButton）：提供水波纹按压反馈
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.control),
          onTap: onPressed,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: filled ? Colors.white : palette.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
