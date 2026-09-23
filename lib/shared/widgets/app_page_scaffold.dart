import 'package:flutter/material.dart';

import 'package:horyx/shared/widgets/app_top_bar.dart';

/// 通用页面骨架：顶栏 + 内容区
/// 统一「AppTopBar 自吸收状态栏 + 内容区 SafeArea 避让左右/底部
/// + Expanded 内容」的纵向结构，页面只需提供标题与内容区
class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    super.key,
    required this.title,
    this.showBack = false,
    required this.child,
  });

  /// 顶栏标题文字
  final String title;

  /// 是否显示返回按钮（二级页面通用样式）
  final bool showBack;

  /// 内容区（顶栏以下的 Expanded 区域）
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // 顶部由 AppTopBar 自行吸收状态栏（表面色整体延伸），此处不再避让
        top: false,
        bottom: false,
        child: Column(
          children: [
            AppTopBar(title: title, showBack: showBack),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
