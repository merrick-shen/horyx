import 'dart:async';

import 'package:flutter/material.dart';

import 'package:horyx/app/game_registry.dart';
import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/app/pages/home_page.dart';
import 'package:horyx/app/pages/more_page.dart';
import 'package:horyx/games/word_pk/services/word_pk_validator.dart';
import 'package:horyx/shared/pages/room_join_page.dart';
import 'package:horyx/shared/update/auto_update_checker.dart';

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
  void initState() {
    super.initState();
    // 预热单词PK词表（约 37 万词）：fire-and-forget 不阻塞首帧——
    // 解析在后台 isolate 中执行，主线程只等待结果，不占启动帧预算；
    // 用户从启动到进入单词PK并提交单词远慢于加载完成，
    // 未加载完成的窗口内 isValid 返回 false 在真实操作路径上不可感知。
    // 放在 app 层骨架而非 main 入口：入口不依赖具体游戏模块，
    // 挂载时机与原先几乎一致（runApp 后首帧）
    unawaited(WordPkValidator.load());
    // 启动后自动检查更新：fire-and-forget，内部已做首帧等待、
    // 3 秒延迟、Debug 短路与异常兜底，失败静默不影响使用
    unawaited(AutoUpdateChecker().checkIfNeeded(context));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 背景用表面色：edge-to-edge 下系统导航栏（手势条）区域透出 Scaffold 背景，
      // 需与底部导航栏同色连成整体；body 区域被各 tab 页自身 Scaffold 完全覆盖，不受影响
      backgroundColor: context.palette.surfaceBg,
      // _PageKeeper 保活：对齐原 IndexedStack 行为，切换/滑动不丢页面状态
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          // 切页时释放焦点收起键盘：联机页输入框聚焦后焦点永久保留，
          // 滑到其他 tab 键盘会悬浮在对方页面上（路由推入的失焦由
          // main.dart 的全局导航观察器处理，此处覆盖 tab 切换路径）
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() => _currentIndex = index);
        },
        children: [
          _PageKeeper(child: HomePage()),
          // 注册表查询由 app 层注入：等待页据此解析图标与联机对局页构建器
          _PageKeeper(child: RoomJoinPage(gameResolver: GameRegistry.byName)),
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
            // 联机 tab：加入房间页（底部导航常驻入口，非页面跳转进入）
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
