import 'package:flutter/material.dart';

import 'package:horyx/shared/widgets/flash_hint.dart';

/// 对局覆盖层提示：全屏居中的渐现渐隐提醒（不拦截触摸），文本为空
/// 不挂载内容。象棋「將軍」与飞行棋对局反馈等各游戏覆盖层场景共用
class HintOverlay extends StatelessWidget {
  const HintOverlay({
    super.key,
    required this.trigger,
    required this.text,
    required this.accentColor,
    required this.fontSize,
    this.letterSpacing = 4,
  });

  /// 触发序号：每递增一次播放一遍动画
  final int trigger;

  /// 提示文本（空串不显示）
  final String text;

  /// 文字光晕色（按提示语义传入）
  final Color accentColor;

  /// 文字字号
  final double fontSize;

  /// 字间距（大字标语可加大）
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: FlashHint(
          trigger: trigger,
          text: text,
          accentColor: accentColor,
          fontSize: fontSize,
          letterSpacing: letterSpacing,
        ),
      ),
    );
  }
}
