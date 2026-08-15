import 'package:flutter/material.dart';

import 'placeholder_page.dart';

/// 主题设置页
/// 主题切换功能待开发，当前复用通用占位页
class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: '主题设置',
      icon: Icons.palette_outlined,
    );
  }
}
