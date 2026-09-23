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
        borderRadius: BorderRadius.circular(Radii.control),
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
          borderRadius: BorderRadius.circular(Radii.control),
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
/// 手动输入合法范围内的数字立即生效（呈选中态）；非空但超范围时红边提示且不生效；
/// 清空后由使用方通过 onCleared 回退默认值。
/// 两侧内置 −/+ 步进按钮：以当前生效值（空输入时以 defaultValue）为基准，
/// 沿方向寻找第一个通过 min/max 与 validate 校验的值——校验有约束时自动
/// 跳过不合法值（如「仅允许奇数」的赛制局数按步进会跳到相邻奇数）；
/// 到达边界或无可达合法值时对应按钮禁用
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
    this.defaultValue,
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

  /// 步进按钮在空输入时的基准值（即使用方清空回退的默认值）；
  /// null 时空输入下步进按钮禁用（无可靠基准）
  final int? defaultValue;

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
    final valid = _isValid(value);
    // 非空且非法 → 红边；有效值生效，无效输入保持上次生效值
    setState(() => _invalid = !valid);
    if (valid) widget.onValid(value!);
  }

  /// 值是否通过 min/max 范围与补充校验
  bool _isValid(int? value) =>
      value != null &&
      value >= widget.min &&
      value <= widget.max &&
      (widget.validate?.call(value) ?? true);

  /// 步进基准：当前输入合法取输入值；空输入取 defaultValue；
  /// 非法输入（红边态）无可靠基准，返回 null
  int? get _stepBase {
    final text = widget.controller.text;
    if (text.isEmpty) return widget.defaultValue;
    final value = int.tryParse(text);
    return _isValid(value) ? value : null;
  }

  /// 基准值沿方向是否存在可达的合法值（跳过 validate 拒绝的值）
  bool _canStep(int? base, int direction) {
    if (base == null) return false;
    var v = base + direction;
    while (v >= widget.min && v <= widget.max) {
      if (_isValid(v)) return true;
      v += direction;
    }
    return false;
  }

  /// 步进：以基准值沿方向找到第一个合法值写入输入框，
  /// 复用手动输入路径（清红边、上报 onValid），保持页面侧语义一致
  void _step(int direction) {
    final base = _stepBase;
    if (base == null) return;
    var v = base + direction;
    while (v >= widget.min && v <= widget.max) {
      if (_isValid(v)) {
        widget.controller.text = '$v';
        _onChanged('$v');
        return;
      }
      v += direction;
    }
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
        // 步进按钮可用性随输入内容即时变化（红边态/无基准时禁用）
        final base = _stepBase;
        final canMinus = _canStep(base, -1);
        final canPlus = _canStep(base, 1);

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: selected ? palette.primary : palette.scaffoldBg,
            borderRadius: BorderRadius.circular(Radii.control),
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
          // Material+InkWell 标准写法（同 PrimaryButton）；
          // ClipRRect 把步进按钮的水波纹裁剪进块的圆角内
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.control),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StepButton(
                    icon: Icons.remove_rounded,
                    selected: selected,
                    palette: palette,
                    onTap: canMinus ? () => _step(-1) : null,
                  ),
                  _blockDivider(selected, palette),
                  // 中段输入区：点击空白区域也可聚焦（原 GestureDetector 语义）
                  Expanded(
                    child: InkWell(
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
                              color: selected
                                  ? Colors.white
                                  : palette.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                            cursorColor: selected
                                ? Colors.white
                                : palette.primary,
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
                  _blockDivider(selected, palette),
                  _StepButton(
                    icon: Icons.add_rounded,
                    selected: selected,
                    palette: palette,
                    onTap: canPlus ? () => _step(1) : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 段间竖分隔线（生效态下随整块反白弱化）
  Widget _blockDivider(bool selected, AppPalette palette) => Container(
    width: 1,
    color: selected ? Colors.white.withValues(alpha: 0.35) : palette.stroke,
  );
}

/// 步进按钮：块内左右两端；生效态（整块主题色填充）时图标反白，
/// 禁用时图标降透明度
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.selected,
    required this.palette,
    this.onTap,
  });

  final IconData icon;
  final bool selected;
  final AppPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : palette.textPrimary;
    return SizedBox(
      width: 56,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Icon(
            icon,
            size: 22,
            color: onTap == null ? color.withValues(alpha: 0.35) : color,
          ),
        ),
      ),
    );
  }
}
