import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 通用选项块：设置项中的可选项方块（如人数、棋盘规格）
/// 选中态品牌纯色实底白字，未选中描边底色
class OptionBlock extends StatelessWidget {
  const OptionBlock({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.fixedWidth,
    this.height = 56,
  });

  /// 选项文案（数字或短文本）
  final String label;

  /// 是否选中
  final bool selected;

  /// 点击回调
  final VoidCallback onTap;

  /// 固定宽度（数字方块场景保持等宽排列）；
  /// 为空时按文案自适应宽度（如「15×15」）
  final double? fixedWidth;

  /// 块高度，默认与原始人数选择块一致
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: fixedWidth,
        height: height,
        // 自适应宽度时以内容撑开，并保留最小可点区域
        constraints: fixedWidth == null
            ? const BoxConstraints(minWidth: 56)
            : null,
        padding: fixedWidth == null
            ? const EdgeInsets.symmetric(horizontal: 16)
            : null,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // 选中态使用品牌纯色，未选中与页面底色区分
          color: selected ? palette.primary : palette.scaffoldBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Colors.transparent : palette.stroke,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: palette.primary.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : palette.textPrimary,
            fontSize: 17,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
