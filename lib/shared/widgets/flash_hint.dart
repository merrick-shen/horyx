import 'package:flutter/material.dart';

import 'package:horyx/shared/theme/app_theme.dart';

/// 全屏居中的渐现渐隐提示：[trigger] 每递增一次播放一遍动画
/// （快速放大淡入 -> 短暂停留 -> 淡出），黑底胶囊 + 白色大字保证醒目，
/// [accentColor] 作文字光晕呼应提示语义（如象棋「將軍」红光晕）
/// 各游戏对局视图共用，覆盖层使用时外包 IgnorePointer 不拦截触摸
class FlashHint extends StatefulWidget {
  const FlashHint({
    super.key,
    required this.trigger,
    required this.text,
    required this.accentColor,
    required this.fontSize,
    this.letterSpacing = 4,
  });

  /// 触发序号：每递增一次播放一遍动画
  final int trigger;

  /// 提示文本
  final String text;

  /// 文字光晕色（按提示语义传入）
  final Color accentColor;

  /// 文字字号（象棋「將軍」大字、飞行棋短句等场景自定）
  final double fontSize;

  /// 字间距（大字标语可加大）
  final double letterSpacing;

  @override
  State<FlashHint> createState() => _FlashHintState();
}

class _FlashHintState extends State<FlashHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didUpdateWidget(covariant FlashHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && widget.trigger > 0) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        // 不透明度：0-15% 淡入，15%-75% 全显，75%-100% 淡出
        final opacity = t < 0.15
            ? t / 0.15
            : t > 0.75
            ? (1 - t) / 0.25
            : 1.0;
        // 淡入期从 1.4 倍缩到 1.0 倍，强化「冲出来」的醒目感
        final scale = t < 0.15 ? 1.4 - 0.4 * (t / 0.15) : 1.0;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Text(
          widget.text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: widget.fontSize,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: widget.letterSpacing,
            shadows: [
              // 语义色光晕 + 黑色锐影，双层阴影保证任何主题下都醒目
              Shadow(
                blurRadius: 18,
                color: widget.accentColor.withValues(alpha: 0.9),
              ),
              const Shadow(blurRadius: 4, color: Colors.black),
            ],
          ),
        ),
      ),
    );
  }
}
