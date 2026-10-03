import 'package:flutter/material.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_colors.dart';
import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';

/// 飞行棋棋子：主色圈 + 白内圆 + 飞机图标（与棋盘停机坪机位原静态装饰
/// 同视觉），尺寸由父层约束决定（填充父给定的正方形空间）
/// [highlighted] 可动高亮（主色光晕）；[selected] 选中态（白描边）
class AeroplanePlane extends StatelessWidget {
  const AeroplanePlane({
    super.key,
    required this.color,
    this.highlighted = false,
    this.selected = false,
    this.onTap,
  });

  /// 棋子颜色
  final AeroplaneColor color;

  /// 可动高亮
  final bool highlighted;

  /// 选中态（白描边）
  final bool selected;

  /// 点击回调；null 表示不可点击
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AeroplaneColors.of(color);
    final plane = LayoutBuilder(
      builder: (context, constraints) {
        final d = constraints.biggest.shortestSide;
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c,
            border: selected
                ? Border.all(color: Colors.white, width: d * 0.09)
                : null,
            boxShadow: highlighted
                ? [
                    BoxShadow(
                      color: c.withValues(alpha: 0.65),
                      blurRadius: d * 0.28,
                      spreadRadius: d * 0.04,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Container(
            width: d * 0.76,
            height: d * 0.76,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.flight_takeoff_rounded,
              color: c,
              size: d * 0.58,
            ),
          ),
        );
      },
    );
    final tap = onTap;
    if (tap == null) {
      return plane;
    }
    return GestureDetector(onTap: tap, child: plane);
  }
}
