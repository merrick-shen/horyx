import 'package:flutter/material.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_colors.dart';
import 'package:horyx/shared/theme/app_theme.dart';

/// 飞行棋 - 图形化点阵骰子
/// 按点数渲染经典点阵骰面（3×3 网格常量表驱动），纯展示组件不参与
/// 对局状态；骰身白底与棋盘卡片同风格（白底 + 主题描边色 +
/// Radii.control 圆角），点色为棋盘固有深色不随主题
class AeroplaneDice extends StatelessWidget {
  const AeroplaneDice({super.key, required this.value, this.size = 80})
      : assert(value >= 1 && value <= 6, '骰面点数必须为 1～6');

  /// 骰面点数（1～6）
  final int value;

  /// 骰子边长（正方形）
  final double size;

  /// 经典点阵布局：3×3 网格归一化坐标（-1/0/1 对应上中下/左中右），
  /// 2/3 沿对角线、6 为两列三点
  static const Map<int, List<Alignment>> _pipLayouts = {
    1: [Alignment(0, 0)],
    2: [Alignment(-1, -1), Alignment(1, 1)],
    3: [Alignment(-1, -1), Alignment(0, 0), Alignment(1, 1)],
    4: [Alignment(-1, -1), Alignment(1, -1), Alignment(-1, 1), Alignment(1, 1)],
    5: [
      Alignment(-1, -1),
      Alignment(1, -1),
      Alignment(0, 0),
      Alignment(-1, 1),
      Alignment(1, 1),
    ],
    6: [
      Alignment(-1, -1),
      Alignment(1, -1),
      Alignment(-1, 0),
      Alignment(1, 0),
      Alignment(-1, 1),
      Alignment(1, 1),
    ],
  };

  /// 点径 = 骰面内边距（占边长比例）：四边留白与相邻点间隙均衡
  static const double _pipRatio = 0.18;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final pip = size * _pipRatio;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: palette.stroke),
      ),
      child: Padding(
        padding: EdgeInsets.all(pip),
        child: Stack(
          children: [
            for (final alignment in _pipLayouts[value]!)
              Align(
                alignment: alignment,
                child: Container(
                  width: pip,
                  height: pip,
                  decoration: const BoxDecoration(
                    color: AeroplaneColors.dicePip,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
