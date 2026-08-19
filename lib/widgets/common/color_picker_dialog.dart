import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 自定义颜色选择器弹窗
/// HSV 三通道（色相/饱和度/亮度）滑块调节 + 实时预览
/// 确定返回所选颜色；取消或关闭返回 null
/// 说明：滑块轨道的色谱过渡是选择器的功能表达（标识可选值范围），
/// 不属于界面装饰渐变
Future<Color?> showColorPickerDialog(
  BuildContext context, {
  required Color initialColor,
}) {
  return showDialog<Color>(
    context: context,
    builder: (_) => _ColorPickerDialog(initialColor: initialColor),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initialColor});

  /// 打开时的初始颜色
  final Color initialColor;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  /// 以 HSV 分量编辑，三个滑块各管一个通道
  late HSVColor _hsv = HSVColor.fromColor(widget.initialColor);

  /// 当前调节结果
  Color get _current => _hsv.toColor();

  /// 当前色相下的纯色（饱和度、亮度均最大），用于绘制饱和度/亮度轨道端点
  Color get _pure => _hsv.withSaturation(1).withValue(1).toColor();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final current = _current;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: palette.surfaceBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '自定义颜色',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            // 实时预览块：底色随滑块变化，文字按亮度自动切换黑白保证可读
            Container(
              height: 68,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: current,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                colorToHex(current),
                style: TextStyle(
                  color: current.computeLuminance() > 0.5
                      ? Colors.black87
                      : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 18),
            _buildSliderRow(
              label: '色相',
              valueText: '${_hsv.hue.round()}°',
              // 色相轨道：0-360° 彩虹色谱
              trackColors: [
                const HSVColor.fromAHSV(1, 0, 1, 1).toColor(),
                const HSVColor.fromAHSV(1, 60, 1, 1).toColor(),
                const HSVColor.fromAHSV(1, 120, 1, 1).toColor(),
                const HSVColor.fromAHSV(1, 180, 1, 1).toColor(),
                const HSVColor.fromAHSV(1, 240, 1, 1).toColor(),
                const HSVColor.fromAHSV(1, 300, 1, 1).toColor(),
                const HSVColor.fromAHSV(1, 360, 1, 1).toColor(),
              ],
              value: _hsv.hue,
              min: 0,
              max: 360,
              onChanged: (v) => setState(() => _hsv = _hsv.withHue(v)),
            ),
            _buildSliderRow(
              label: '饱和度',
              valueText: '${(_hsv.saturation * 100).round()}%',
              // 饱和度轨道：灰白 → 当前色相纯色
              trackColors: [Colors.white, _pure],
              value: _hsv.saturation,
              min: 0,
              max: 1,
              onChanged: (v) =>
                  setState(() => _hsv = _hsv.withSaturation(v.clamp(0, 1))),
            ),
            _buildSliderRow(
              label: '亮度',
              valueText: '${(_hsv.value * 100).round()}%',
              // 亮度轨道：黑 → 当前色相纯色
              trackColors: [Colors.black, _pure],
              value: _hsv.value,
              min: 0,
              max: 1,
              onChanged: (v) =>
                  setState(() => _hsv = _hsv.withValue(v.clamp(0, 1))),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _PickerButton(
                    label: '取消',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PickerButton(
                    label: '确定',
                    filled: true,
                    fillColor: current,
                    onPressed: () => Navigator.of(context).pop(current),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 单个通道滑块行：标签 + 谱轨滑块 + 数值
  Widget _buildSliderRow({
    required String label,
    required String valueText,
    required List<Color> trackColors,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 10,
                // 轨道整条绘制色谱，不区分激活/非激活段
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white,
                thumbColor: _current,
                overlayColor: _current.withValues(alpha: 0.12),
                trackShape: _SpectrumTrackShape(colors: trackColors),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              valueText,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 谱轨滑块轨道：整条轨道以传入颜色列表做线性色谱绘制
class _SpectrumTrackShape extends RoundedRectSliderTrackShape {
  const _SpectrumTrackShape({required this.colors});

  final List<Color> colors;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    double additionalActiveTrackHeight = 0,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 8;
    final trackWidth = parentBox.size.width;
    // 轨道垂直居中于滑块可用区
    final rect = Rect.fromLTWH(
      offset.dx,
      offset.dy + (parentBox.size.height - trackHeight) / 2,
      trackWidth,
      trackHeight,
    );
    final paint = Paint()
      ..shader = LinearGradient(colors: colors).createShader(rect);
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(trackHeight / 2)),
      paint,
    );
  }
}

/// 弹窗底部按钮：样式与确认弹窗按钮一致（描边 / 实底）
class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.fillColor,
  });

  final String label;
  final VoidCallback onPressed;

  /// 是否实底主按钮样式
  final bool filled;

  /// 实底颜色（默认品牌色）
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
