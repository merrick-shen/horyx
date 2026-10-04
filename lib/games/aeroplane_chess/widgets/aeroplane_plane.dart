import 'package:flutter/material.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_colors.dart';
import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';

/// 飞行棋棋子：主色圈 + 白内圆 + 图标（未完成显示飞机、已完成显示勾）
/// （与棋盘停机坪机位原静态装饰同视觉），尺寸由父层约束决定
/// （填充父给定的正方形空间）
/// [highlighted] 可动高亮：呼吸脉冲提示可点；[selected] 选中态：白描边
class AeroplanePlane extends StatefulWidget {
  const AeroplanePlane({
    super.key,
    required this.color,
    this.finished = false,
    this.highlighted = false,
    this.selected = false,
    this.onTap,
  });

  /// 棋子颜色
  final AeroplaneColor color;

  /// 已完成（抵达终点飞回基地）：图标显示勾
  final bool finished;

  /// 可动高亮（呼吸脉冲）
  final bool highlighted;

  /// 选中态（白描边）
  final bool selected;

  /// 点击回调；null 表示不可点击
  final VoidCallback? onTap;

  @override
  State<AeroplanePlane> createState() => _AeroplanePlaneState();
}

class _AeroplanePlaneState extends State<AeroplanePlane>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.highlighted) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant AeroplanePlane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlighted != oldWidget.highlighted) {
      if (widget.highlighted) {
        _pulse.repeat(reverse: true);
      } else {
        _pulse.stop();
      }
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 棋子用加深变体色，停己色格/基地上不与底色融合
    final c = AeroplaneColors.pieceOf(widget.color);
    final plane = AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        // 呼吸脉冲：1.0 -> 1.12 缩放
        return Transform.scale(scale: 1.0 + 0.12 * _pulse.value, child: child);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final d = constraints.biggest.shortestSide;
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c,
              border: widget.selected
                  ? Border.all(color: Colors.white, width: d * 0.09)
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
                widget.finished
                    ? Icons.check_rounded
                    : Icons.flight_takeoff_rounded,
                color: c,
                size: d * 0.58,
              ),
            ),
          );
        },
      ),
    );
    final tap = widget.onTap;
    if (tap == null) {
      return plane;
    }
    return GestureDetector(onTap: tap, child: plane);
  }
}
