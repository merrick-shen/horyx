import 'package:flutter/material.dart';

import 'package:horyx/games/tank/models/tank_player.dart';

/// 原版同款四向摇杆：灰色四箭头底座（素材原色）+ 玩家色中心钮（白模染色）
/// 拖动超过死区后按主导轴判定方向，方向变化才回调；松手回中并回调 null
class TankJoystick extends StatefulWidget {
  const TankJoystick({
    super.key,
    required this.color,
    required this.onDirection,
    this.size = 140,
  });

  /// 中心钮染色（玩家色）
  final Color color;

  /// 方向变化回调；null 表示松手回中（战场实现后驱动坦克移动）
  final ValueChanged<TankMoveDirection?> onDirection;

  /// 底座直径
  final double size;

  @override
  State<TankJoystick> createState() => _TankJoystickState();
}

class _TankJoystickState extends State<TankJoystick> {
  /// 中心钮当前偏移（相对底座中心）
  Offset _offset = Offset.zero;

  /// 上次回调的方向（仅在变化时回调，避免拖动过程逐帧重复通知）
  TankMoveDirection? _lastNotified;

  /// 中心钮直径（保持素材原图 160/325 的比例）
  double get _knobSize => widget.size * 160 / 325;

  /// 钮心最大拖动半径（钮不脱出底座）
  double get _maxDrag => (widget.size - _knobSize) / 2;

  /// 死区半径：拖动距离低于此值视为无方向
  double get _deadZone => widget.size * 0.12;

  void _onPanUpdate(DragUpdateDetails details) {
    final raw = details.localPosition - Offset(widget.size / 2, widget.size / 2);
    setState(() => _offset = _clampToBase(raw));
    _notifyIfNeeded(_directionOf(raw));
  }

  void _onPanEnd(DragEndDetails details) => _reset();

  void _onPanCancel() => _reset();

  /// 松手回中并撤销方向
  void _reset() {
    setState(() => _offset = Offset.zero);
    _notifyIfNeeded(null);
  }

  /// 钮的显示位置限制在底座内（方向判定用未收敛的原始向量）
  Offset _clampToBase(Offset offset) {
    final length = offset.distance;
    if (length <= _maxDrag || length == 0) return offset;
    return offset * (_maxDrag / length);
  }

  /// 主导轴判定方向（坦克只能前进/后退/原地转向，不做斜向）
  TankMoveDirection? _directionOf(Offset offset) {
    if (offset.distance < _deadZone) return null;
    if (offset.dx.abs() > offset.dy.abs()) {
      return offset.dx > 0
          ? TankMoveDirection.turnRight
          : TankMoveDirection.turnLeft;
    }
    return offset.dy > 0
        ? TankMoveDirection.backward
        : TankMoveDirection.forward;
  }

  void _notifyIfNeeded(TankMoveDirection? direction) {
    if (direction == _lastNotified) return;
    _lastNotified = direction;
    widget.onDirection(direction);
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
        child: Stack(
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
