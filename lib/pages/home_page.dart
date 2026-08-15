import 'package:flutter/material.dart';

import '../widgets/game_grid.dart';
import '../widgets/home_nav_bar.dart';

/// 主页：导航栏 + 游戏列表
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const HomeNavBar(),
      // 内容可能超出一屏（游戏卡片分多行），需要滚动容器承载
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: const GameGrid(),
      ),
    );
  }
}
