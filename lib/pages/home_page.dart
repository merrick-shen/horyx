import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/game_grid.dart';
import '../widgets/home_nav_bar.dart';

/// 主页：导航栏 + 游戏列表
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 深色背景下状态栏图标使用浅色，保证时间/电量等信息可读
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const HomeNavBar(),
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
      ),
    );
  }
}
