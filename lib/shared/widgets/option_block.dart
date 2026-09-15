import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:horyx/shared/theme/app_theme.dart';

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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: fixedWidth,
      height: height,
      // 自适应宽度时以内容撑开，并保留最小可点区域
      constraints: fixedWidth == null
          ? const BoxConstraints(minWidth: 56)
          : null,
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
      // Material+InkWell 标准写法（同 PrimaryButton）：水波纹覆盖整块；
      // 原容器 padding/alignment 内移到内容层，避免水波纹仅覆盖文字区域
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Center(
            child: Padding(
              padding: fixedWidth == null
                  ? const EdgeInsets.symmetric(horizontal: 16)
                  : EdgeInsets.zero,
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : palette.textPrimary,
                  fontSize: 17,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 数字输入选项块：与 OptionBlock 同规格，但值由数字输入决定（如计分器比分设置）
/// 输入合法范围内的数字立即生效（呈选中态）；非空但超范围时红边提示且不生效；
/// 清空后由使用方通过 onCleared 回退默认值
class NumberOptionBlock extends StatefulWidget {
  const NumberOptionBlock({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.min,
    required this.max,
    required this.onValid,
    required this.onCleared,
    this.validate,
    this.width = double.infinity,
    this.height = 56,
  });

  /// 输入框控制器（初始文本由使用方预填默认值）
  final TextEditingController controller;

  /// 输入焦点（聚焦时以主题色描边提示输入中）
  final FocusNode focusNode;

  /// 空输入提示文案
  final String hintText;

  /// 合法范围（闭区间）
  final int min;
  final int max;

  /// 输入合法值回调
  final ValueChanged<int> onValid;

  /// 输入清空回调
  final VoidCallback onCleared;

  /// min/max 范围校验之后的补充校验（如「仅允许奇数」）：
  /// 返回 false 时与超范围同等处理——红边提示且不生效；null 时只查范围
  final bool Function(int value)? validate;

  /// 块宽度（默认撑满面板宽度，保持与面板等宽的大输入区域）
  final double width;

  /// 块高度，与 OptionBlock 默认高度一致
  final double height;

  /// 超范围提示色（固定红，深浅主题下均醒目，不随主题色变化）
  static const Color _invalidColor = Color(0xFFE5484D);

  @override
  State<NumberOptionBlock> createState() => _NumberOptionBlockState();
}

class _NumberOptionBlockState extends State<NumberOptionBlock> {
  /// 输入非空但超出合法范围时置位（红边提示）
  bool _invalid = false;

  void _onChanged(String raw) {
    if (raw.isEmpty) {
      if (_invalid) setState(() => _invalid = false);
      widget.onCleared();
      return;
    }
    final value = int.tryParse(raw);
    final valid = value != null &&
        value >= widget.min &&
        value <= widget.max &&
        (widget.validate?.call(value) ?? true);
    // 非空且非法 → 红边；有效值生效，无效输入保持上次生效值
    setState(() => _invalid = !valid);
    if (valid) widget.onValid(value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AnimatedBuilder(
      // 监听焦点：聚焦未生效时以主题色描边提示输入中
      animation: widget.focusNode,
      builder: (context, _) {
        final focused = widget.focusNode.hasFocus;
        // 有合法内容即生效选中态；超范围时不呈选中（避免误导已生效）
        final selected = widget.controller.text.isNotEmpty && !_invalid;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: selected ? palette.primary : palette.scaffoldBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _invalid
                  ? NumberOptionBlock._invalidColor
                  : selected
                  ? Colors.transparent
                  : focused
                  ? palette.primary
                  : palette.stroke,
              width: _invalid ? 1.6 : 1,
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
          // Material+InkWell 标准写法（同 PrimaryButton）：点击块内空白
          // 区域也可聚焦（原 GestureDetector 语义），水波纹覆盖整块；
          // 原容器 padding/alignment 内移到内容层
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => widget.focusNode.requestFocus(),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    keyboardType: TextInputType.number,
                    // 仅数字且最多 2 位（调用方范围上限均为两位数以内，超长输入无意义）
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? Colors.white : palette.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                    cursorColor: selected ? Colors.white : palette.primary,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: widget.hintText,
                      hintStyle: TextStyle(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.75)
                            : palette.textSecondary,
                        fontSize: 13,
                      ),
                      counterText: '',
                    ),
                    onChanged: _onChanged,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
