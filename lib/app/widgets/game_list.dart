import 'package:flutter/material.dart';

import 'package:horyx/app/game_registry.dart';
import 'package:horyx/app/widgets/game_card.dart';

/// 游戏列表区域：单行单列的长方形卡片纵向排列
class GameList extends StatelessWidget {
  const GameList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      // 作为页面滚动容器的子项嵌入，关闭自身滚动并收缩高度
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: GameRegistry.games.length,
      itemBuilder: (context, index) {
        final game = GameRegistry.games[index];
        return GameCard(
          game: game,
          // 跳转目标来自注册表（GameRegistry），本组件不感知具体游戏页
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: game.pageBuilder),
          ),
        );
      },
      separatorBuilder: (context, index) => const SizedBox(height: 16),
    );
  }
}
