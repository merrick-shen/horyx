import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 坦克对局控制列（本地页与联机页共用骨架）：
/// 单列三行等高槽位（上/中/下），小控件（开火钮/比分）在槽内居中。
/// 槽位内容参数化，null 为空槽占位（联机页镜像保位用，宽高与等高槽一致）；
/// 两列中心对称的整体布局语义见各对局页
class TankControlColumn extends StatelessWidget {
  const TankControlColumn({
    super.key,
    required this.slotHeight,
    this.top,
    this.middle,
    this.bottom,
  });

  /// 等高槽位高度（由 [slotHeightFor] 计算，调用方传入）
  final double slotHeight;

  /// 上/中/下槽位内容；null 为空槽
  final Widget? top;
  final Widget? middle;
  final Widget? bottom;

  /// 摇杆列四周留白：圆钮推出底座时会越过摇杆区域约半个钮径
  /// （最大约槽高 12%+，[_maxSlotHeight] 槽时约 34px），留白必须覆盖之——
  /// 否则圆钮会被后绘制的地图区盖住、下方会伸出屏幕外
  static const double _panelPadding = 40;

  /// 槽高下限：小屏防控件过小，保证摇杆/开火钮可触面积
  static const double _minSlotHeight = 104;

  /// 槽高上限：大屏不无限放大，维持观感比例
  static const double _maxSlotHeight = 140;

  /// 三行等高槽位随屏幕高度收缩（区间 [_minSlotHeight, _maxSlotHeight]），
  /// 避免固定槽高在小屏横屏下纵向溢出；
  /// 80 = 摇杆列上下留白（[_panelPadding]）×2
  static double slotHeightFor(double maxHeight) =>
      math.max(_minSlotHeight, math.min(_maxSlotHeight, (maxHeight - 80) / 3));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(_panelPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [_slot(top), _slot(middle), _slot(bottom)],
      ),
    );
  }

  /// 等高槽位：内容在槽内居中；空槽给与摇杆等宽的固定占位保证列宽稳定
  Widget _slot(Widget? child) => SizedBox(
        height: slotHeight,
        width: child == null ? slotHeight : null,
        child: child == null ? null : Center(child: child),
      );
}
