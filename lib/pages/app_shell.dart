import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'home_page.dart';
import 'more_page.dart';
import 'lan/room_list_page.dart';

/// 应用根骨架：底部导航栏 + 首页/联机/更多页切换
/// 页面切换使用 PageView 支持左右滑动手势：
/// - 左滑切到下一页、右滑切回上一页，拖动不足自动回弹
/// - 页面用保活包装，与原 IndexedStack 一样不丢页面状态
/// 状态栏样式由 MaterialApp 的 builder 统一处理（随主题亮度变化）
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final PageController _pageController = PageController(initialPage: 0);
  int _currentIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // _PageKeeper 保活：对齐原 IndexedStack 行为，切换/滑动不丢页面状态
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        children: [
          _PageKeeper(child: HomePage()),
          _PageKeeper(child: RoomListPage()),
          _PageKeeper(child: MorePage()),
        ],
      ),
      // 顶部描边与顶部导航栏呼应，其余配色由全局主题统一提供
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.palette.stroke)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          // 导航点击与手势滑动共用同一 PageController，带平滑过渡动画
          onDestinationSelected: (index) => _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          ),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: '首页',
            ),
            // 联机 tab：局域网房间列表（底部导航常驻入口，非页面跳转进入）
            NavigationDestination(
              icon: Icon(Icons.lan_outlined),
              selectedIcon: Icon(Icons.lan_rounded),
              label: '联机',
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

/// 保活包装：PageView 滑出视口的页面默认会被销毁，
/// 通过 KeepAliveNotification 通知 PageView 内置的保活机制保留页面状态
/// （不能直接用 KeepAlive ParentDataWidget：会被 DecoratedBox 隔断误用）
class _PageKeeper extends StatefulWidget {
  final Widget child;

  const _PageKeeper({required this.child});

  @override
  State<_PageKeeper> createState() => _PageKeeperState();
}

class _PageKeeperState extends State<_PageKeeper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
