import 'package:flutter/material.dart';

/// 游戏设置视图骨架：内容限宽居中（maxWidth 520，平板/桌面端）+ 统一边距
/// 各游戏 setup_view 共用的外层结构；
/// 设置面板较多时（如计分器）启用 [scrollable] 允许小屏滚动，
/// 否则以最小高度在页面垂直居中
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
    final content = Column(
      mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    return SizedBox.expand(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: scrollable
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: content,
                )
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: content,
                ),
        ),
      ),
    );
  }
}
