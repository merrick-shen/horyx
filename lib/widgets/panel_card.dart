import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 通用面板卡片：游戏设置项的容器样式（卡片底 + 描边 + 圆角）
/// 单词PK、五子棋等游戏的设置视图复用，保证视觉统一
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.stroke),
      ),
      child: child,
    );
  }
}
