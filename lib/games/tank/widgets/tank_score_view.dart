import 'package:flutter/material.dart';

import 'package:horyx/games/tank/models/tank_player.dart';
import 'package:horyx/shared/theme/app_theme.dart';

/// 比分显示：侧视小坦克图标（烘焙白模染色）+ 比分数字
/// 复刻原版两列中心对称：左列图标朝右、数字在右；右列图标朝左、数字在左
/// （图标素材原生朝左，默认列水平翻转为朝右）
class TankScoreView extends StatelessWidget {
  const TankScoreView({
    super.key,
    required this.player,
    required this.score,
    this.mirrored = false,
  });

  /// 归属玩家（决定图标染色）
  final TankPlayer player;

  /// 当前比分
  final int score;

  /// 是否右列（镜像侧）：图标保持素材朝向（朝左），数字在图标左侧
  final bool mirrored;

  /// 坦克图标高度（宽随素材 380:204 比例）
  static const double _iconHeight = 36;

  @override
  Widget build(BuildContext context) {
    final icon = ColorFiltered(
      colorFilter: tintFilter(player.color),
      child: Transform.flip(
        flipX: !mirrored,
        child: Image.asset(
          'assets/tank/tank_icon.png',
          height: _iconHeight,
          fit: BoxFit.contain,
        ),
      ),
    );
    final number = Text(
      '$score',
      style: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        color: context.palette.textPrimary,
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: mirrored
          ? [number, const SizedBox(width: 10), icon]
          : [icon, const SizedBox(width: 10), number],
    );
  }
}
