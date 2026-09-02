import 'package:flutter/material.dart';

/// 页面内容宽度约束：内容限宽居中（maxWidth 520，平板/桌面端适配）+ 统一页边距
/// 全项目各设置页/对局页共用的外层结构，宽度与边距只在此一处维护；
/// [scrollable] 为 true 时以滚动容器承载内容（设置项较多、小屏需滑动的页面）
class PageContent extends StatelessWidget {
  const PageContent({
    super.key,
    required this.child,
    this.scrollable = false,
    this.padding = const EdgeInsets.all(20),
  });

  /// 页面内容
  final Widget child;

  /// 内容可能超出屏幕高度时启用滚动
  final bool scrollable;

  /// 页边距（滚动模式下作用于滚动容器，保证滚动到边缘仍有留白）
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (scrollable) {
      content = SingleChildScrollView(padding: padding, child: child);
    } else {
      content = Padding(padding: padding, child: child);
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: content,
      ),
    );
  }
}
