import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:horyx/games/tank/models/tank_player.dart';

/// 原版同款摇杆：灰色四箭头底座（素材原色）+ 玩家色中心钮（白模染色）。
/// 原版操控语义：圆钮未超出底座边界时坦克只旋转（转向摇杆指向的角度），
/// 超出底座边界后坦克沿摇杆指向前进（转向与前进并行，走弧线）；松手回中即停车。
class TankJoystick extends StatefulWidget {
  const TankJoystick({
    super.key,
    required this.color,
    required this.onDrive,
    this.size = 140,
  });

  /// 中心钮染色（玩家色）
  final Color color;

  /// 驾驶输入回调；null 表示摇杆回中（停车）
  final ValueChanged<TankDriveInput?> onDrive;

  /// 底座直径
  final double size;

  @override
  State<TankJoystick> createState() => _TankJoystickState();
}

class _TankJoystickState extends State<TankJoystick> {
  /// 中心钮当前偏移（相对底座中心）
  Offset _offset = Offset.zero;

  /// 中心钮直径（保持素材原图 160/325 的比例）
  double get _knobSize => widget.size * 160 / 325;

  /// 钮的最大显示偏移：圆钮中心推到底座边缘，
  /// 即最多半个圆钮露出底座外（"超出底座一半"）
  double get _maxDrag => widget.size / 2;

  /// 死区半径：拖动距离低于此值视为回中（中心附近角度抖动无意义）
  double get _deadZone => widget.size * 0.12;

  void _onPanUpdate(DragUpdateDetails details) {
    final raw =
        details.localPosition - Offset(widget.size / 2, widget.size / 2);
    // 钮的显示位置限制在底座内（超界判定用未收敛的原始向量）
    setState(() => _offset = _clampToBase(raw));

    if (raw.distance < _deadZone) {
      widget.onDrive(null);
      return;
    }
    widget.onDrive(
      TankDriveInput(
        targetAngle: math.atan2(raw.dy, raw.dx),
        // 圆钮边缘刚触及底座边缘即算"超出"（视觉上一冒头就前进）
        move: raw.distance > widget.size / 2 - _knobSize / 2,
      ),
    );
  }

  void _onPanEnd(DragEndDetails details) => _reset();

  void _onPanCancel() => _reset();

  /// 松手回中即停车
  void _reset() {
    setState(() => _offset = Offset.zero);
    widget.onDrive(null);
  }

  Offset _clampToBase(Offset offset) {
    final length = offset.distance;
    if (length <= _maxDrag || length == 0) return offset;
    return offset * (_maxDrag / length);
  }

  @override
  Widget build(BuildContext context) {
    final knobSize = _knobSize;
    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onPanCancel: _onPanCancel,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        // 圆钮推出底座边缘后会超出本区域，取消默认裁剪保证完整可见
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Image.asset(
              'assets/tank/joystick_base.png',
              width: widget.size,
              height: widget.size,
            ),
            Positioned(
              left: (widget.size - knobSize) / 2 + _offset.dx,
              top: (widget.size - knobSize) / 2 + _offset.dy,
              child: ColorFiltered(
                colorFilter: tintFilter(widget.color),
                child: Image.asset(
                  'assets/tank/joystick_knob.png',
                  width: knobSize,
                  height: knobSize,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
