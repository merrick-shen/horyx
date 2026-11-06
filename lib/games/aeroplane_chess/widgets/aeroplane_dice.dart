import 'dart:async';
import 'dart:math';

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

/// 骰面翻动动画器：80ms × 10 帧随机翻动后定格最终骰点，本地与联机
/// 对局页共用。每帧经 [onTick] 上抛随机骰面、定格经 [onSettled] 上抛
/// 最终点数（宿主自行 setState 更新展示）；翻动中再次 start 会先取消
/// 上一轮。宿主须在 dispose 时 [cancel]，计时器随宿主生命周期终止
class AeroplaneDiceRollAnimator {
  AeroplaneDiceRollAnimator({
    required this.onTick,
    required this.onSettled,
  });

  /// 每帧上抛随机骰面
  final void Function(int face) onTick;

  /// 定格上抛最终点数
  final void Function(int result) onSettled;

  Timer? _timer;
  final Random _random = Random();

  /// 开始翻动；[result] 为定格骰点（联机广播值），缺省时翻动结束时
  /// 随机生成（本地掷骰）
  void start({int? result}) {
    cancel();
    var ticks = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      ticks++;
      if (ticks < 10) {
        onTick(_random.nextInt(6) + 1);
        return;
      }
      timer.cancel();
      _timer = null;
      onSettled(result ?? _random.nextInt(6) + 1);
    });
  }

  /// 终止翻动（此后不再回调）
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
