import 'package:flutter/material.dart';

import 'stone_board.dart';
import 'turn_card.dart';

/// 棋类执子提示卡：封装 TurnCard 在黑白棋对局中的通用推导
/// （对局中显示当前执子方，终局显示胜方；图标颜色对应棋子颜色）
/// 五子棋本地/联机与围棋三个棋盘视图共用，消除各自的重复三目推导
class StoneTurnCard extends StatelessWidget {
  const StoneTurnCard({
    super.key,
    required this.isOver,
    required this.blackToMove,
    required this.winner,
    required this.subtitle,
  });

  /// 是否终局
  final bool isOver;

  /// 对局中当前执黑方（终局后无意义）
  final bool blackToMove;

  /// 胜方（'黑方'/'白方'）；对局进行中为 null
  final String? winner;

  /// 对局中副标题（各棋类文案不同，如「当前执子」「轮到你落子」）
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    // 终局图标色跟随胜方棋子颜色（五子棋胜方即最后一手方，围棋数子判胜，
    // 两者的 winner 文本均直接对应棋子颜色，推导可统一）
    final title = isOver ? '$winner胜利' : (blackToMove ? '黑方' : '白方');
    return TurnCard(
      icon: Icons.circle_rounded,
      iconColor: (isOver ? winner == '黑方' : blackToMove)
          ? StoneBoard.blackStone
          : StoneBoard.whiteStone,
      subtitle: isOver ? '对局结束' : subtitle,
      title: title,
      titleKey: ValueKey(title),
    );
  }
}
