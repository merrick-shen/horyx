import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:horyx/games/tank/widgets/tank_control_column.dart';

/// 左右控制列构建回调（[slotHeight] 为骨架计算的等高槽高，
/// 摇杆等随槽高缩放的控件以此为尺寸）
typedef TankColumnBuilder = TankControlColumn Function(double slotHeight);

/// 坦克对局页战场布局骨架（本地与联机对局页共用）：
/// 横屏挖孔/刘海单侧 inset 取大避让（不用 SafeArea——横屏下只在一侧
/// 产生 inset，取较大值才能保证左右操作区到屏幕边缘的距离完全对称），
/// 左右两列控制 + 中央战场；列槽位内容经 [TankColumnBuilder] 参数化，
/// 由调用方组装（null 为空槽，占位保位见 [TankControlColumn]）
class TankBattleLayout extends StatelessWidget {
  const TankBattleLayout({
    super.key,
    required this.battle,
    required this.leftColumn,
    required this.rightColumn,
  });

  /// 中央战场区域（Flame GameWidget）
  final Widget battle;

  /// 左右控制列（三槽等高：上/中/下，槽位组装见各对局页）
  final TankColumnBuilder leftColumn;
  final TankColumnBuilder rightColumn;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final insets = MediaQuery.of(context).padding;
        final hCutout = math.max(insets.left, insets.right);
        final slotHeight =
            TankControlColumn.slotHeightFor(constraints.maxHeight);
        return Padding(
          padding: EdgeInsets.fromLTRB(hCutout, 0, hCutout, 0),
          child: Row(
            children: [
              leftColumn(slotHeight),
              Expanded(child: battle),
              rightColumn(slotHeight),
            ],
          ),
        );
      },
    );
  }
}
