import 'package:flutter/material.dart';

import '../data/game_data.dart';
import '../pages/gomoku_page.dart';
import '../pages/placeholder_page.dart';
import '../pages/scoreboard_page.dart';
import '../pages/word_pk_page.dart';
import 'game_card.dart';

/// 游戏列表区域：根据可用宽度自动切换列数（响应式布局）
/// 手机 2 列 / 平板 3 列 / 小桌面 4 列 / 大桌面 5 列
class GameGrid extends StatelessWidget {
  const GameGrid({super.key});

  /// 依据可用宽度计算列数
  int _columnsFor(double width) {
    if (width < 600) return 2;
    if (width < 900) return 3;
    if (width < 1200) return 4;
    return 5;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          // 作为页面滚动容器的子项嵌入，关闭自身滚动并收缩高度
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _columnsFor(constraints.maxWidth),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            // 固定卡片高度而非宽高比：
            // 卡片内容高度是定值，固定高度可保证任意列数下都不溢出
            mainAxisExtent: 212,
          ),
          itemCount: GameData.games.length,
          itemBuilder: (context, index) => GameCard(
            game: GameData.games[index],
            // 已接入玩法的游戏卡片跳转对应游戏页；
            // 已规划未开发的游戏进入占位页
            onTap: switch (index) {
              0 => () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WordPkPage(),
                    ),
                  ),
              1 => () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const GomokuPage(),
                    ),
                  ),
              2 => () => Navigator.of(context).push(
                    MaterialPageRoute(
                      // 标题与图标复用游戏卡片数据，保持两处一致
                      builder: (_) => PlaceholderPage(
                        title: GameData.weiqi.name,
                        icon: GameData.weiqi.icon,
                      ),
                    ),
                  ),
              // 计分器：比分设置 + 横屏计分板
              3 => () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ScoreboardPage(),
                    ),
                  ),
              // 列表仅四个游戏，此处为 switch 穷尽性兜底
              _ => null,
            },
          ),
        );
      },
    );
  }
}
