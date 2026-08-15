import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'home_page.dart';
import 'more_page.dart';

/// 应用根骨架：底部导航栏 + 首页/更多页切换
/// 状态栏样式由 MaterialApp 的 builder 统一处理（随主题亮度变化）
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack 保持各页面状态，切换标签时不丢失滚动位置
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          HomePage(),
          MorePage(),
        ],
      ),
      // 顶部描边与顶部导航栏呼应，其余配色由全局主题统一提供
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.palette.stroke)),
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
    );
  }
}
