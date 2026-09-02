import 'package:flutter/material.dart';

import 'package:horyx/shared/widgets/page_content.dart';

/// 游戏设置视图骨架：内容限宽居中 + 统一页边距（复用 [PageContent]），
/// 以最小高度在页面垂直居中；面板较多的页面（如计分器）启用 [scrollable]
/// 允许小屏滚动查看全部设置项
class SetupScaffold extends StatelessWidget {
  const SetupScaffold({
    super.key,
    required this.children,
    this.scrollable = false,
  });

  /// 设置内容（恢复卡片、设置面板、主按钮等；块间距由调用方以 SizedBox 控制）
  final List<Widget> children;

  /// 面板较多时启用滚动，小屏设备可滑动查看全部设置项
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: PageContent(
        scrollable: scrollable,
        child: Column(
          mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
