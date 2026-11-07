import 'package:flutter/material.dart';

import 'package:horyx/shared/widgets/app_top_bar.dart';

/// 本地对局页骨架（各游戏本地页共用，与联机页骨架 OnlineGamePageShell
/// 平行）：PopScope 返回拦截 + 统一顶栏 + 设置/对局两阶段视图
/// AnimatedSwitcher 切换。[canPop] 为 true 时系统返回直接放行（设置阶段/
/// 终局查看阶段），false 时拦截转交 [onRequestExit] 走退出确认流程；
/// 顶栏返回同样走 [onRequestExit]。顶部由 [AppTopBar] 自行吸收状态栏
/// （表面色整体延伸），SafeArea 不再避让
class LocalGamePageShell extends StatelessWidget {
  const LocalGamePageShell({
    super.key,
    required this.title,
    required this.started,
    required this.canPop,
    required this.onRequestExit,
    required this.setupBuilder,
    required this.gameBuilder,
  });

  /// 顶栏标题（游戏名）
  final String title;

  /// 是否已进入对局（false 展示设置视图）
  final bool started;

  /// 系统返回是否直接放行
  final bool canPop;

  /// 顶栏返回与被拦截的系统返回统一走退出确认
  final VoidCallback onRequestExit;

  /// 设置视图构建（懒构建，仅设置阶段调用）
  final WidgetBuilder setupBuilder;

  /// 对局视图构建（懒构建，仅对局阶段调用）
  final WidgetBuilder gameBuilder;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onRequestExit();
      },
      child: Scaffold(
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              AppTopBar(title: title, showBack: true, onBack: onRequestExit),
              Expanded(
                // 阶段切换动画：设置视图 <-> 对局视图（两视图各自带
                // 'setup'/'board' ValueKey 驱动切换动画）
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: started ? gameBuilder(context) : setupBuilder(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
