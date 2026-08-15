import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'home_page.dart';
import 'settings_page.dart';

/// 应用根骨架：底部导航栏 + 首页/设置页切换
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 深色背景下状态栏图标使用浅色，保证时间/电量等信息可读
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        // IndexedStack 保持各页面状态，切换标签时不丢失滚动位置
        body: IndexedStack(
          index: _currentIndex,
          children: const [
            HomePage(),
            SettingsPage(),
          ],
        ),
        // 顶部描边与顶部导航栏呼应，其余配色由全局主题统一提供
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.stroke)),
          ),
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) =>
                setState(() => _currentIndex = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: '首页',
              ),
              NavigationDestination(
                icon: Icon(Icons.more_horiz_outlined),
                selectedIcon: Icon(Icons.more_horiz_rounded),
                label: '更多',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
