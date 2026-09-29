import 'package:flutter/material.dart';

import 'package:horyx/games/chess/models/chess_piece.dart';
import 'package:horyx/shared/theme/app_theme.dart';

/// 「将军」渐现渐隐提示：[trigger] 每递增一次播放一遍动画
/// （快速放大淡入 -> 短暂停留 -> 淡出），黑底胶囊 + 白色大字保证醒目
/// 本地对局视图与联机对局视图共用
class CheckFlashText extends StatefulWidget {
  const CheckFlashText({super.key, required this.trigger});

  final int trigger;

  @override
  State<CheckFlashText> createState() => _CheckFlashTextState();
}

class _CheckFlashTextState extends State<CheckFlashText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didUpdateWidget(covariant CheckFlashText oldWidget) {
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
          child: Transform.scale(
            scale: scale,
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Text(
          '將軍',
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 10,
            shadows: [
              // 红色光晕 + 黑色锐影，双层阴影保证任何主题下都醒目
              Shadow(
                blurRadius: 18,
                color: ChessPieceColors.red.withValues(alpha: 0.9),
              ),
              const Shadow(blurRadius: 4, color: Colors.black),
            ],
          ),
        ),
      ),
    );
  }
}
