import 'package:flutter/material.dart';

import '../widgets/common/app_top_bar.dart';
import '../widgets/home/game_grid.dart';

/// 主页：导航栏 + 游戏列表
/// 状态栏样式与底部导航由外层 AppShell 统一管理
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AppTopBar(title: 'Horyx'),
            // 内容可能超出一屏（游戏卡片分多行），需要滚动容器承载
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: const GameGrid(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
