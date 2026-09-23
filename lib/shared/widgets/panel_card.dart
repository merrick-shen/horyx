import 'package:flutter/material.dart';

import 'package:horyx/shared/theme/app_theme.dart';

/// 通用面板卡片：卡片底 + 描边 + 圆角的统一容器样式
/// 游戏设置视图与设置页/更多页等各处卡片复用，保证视觉统一
class PanelCard extends StatelessWidget {
  const PanelCard({super.key, required this.child, this.padding});

  /// 面板内容
  final Widget child;

  /// 内边距；默认与各游戏设置卡片一致
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.surfaceBg,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: context.palette.stroke),
      ),
      child: child,
    );
  }
}
