import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'package:horyx/games/tank/game/tank.dart';
import 'package:horyx/games/tank/models/tank_player.dart';

/// 子弹实体：从炮口沿车身朝向射出，无限反弹，发射 9 秒后消失。
/// 状态存于迷宫坐标系（[logicalPos] 单位=格，原点迷宫左上角），
/// 与画布尺寸无关，渲染由战场按逻辑状态驱动。
/// 与墙的碰撞为圆形 vs 墙矩形（最近点法）：命中即沿墙面法线反射，
/// 子步进推进防穿薄墙；不做子弹间碰撞，命中坦克判定随回合系统接入。
/// 到期后仅标记 [expired]，移除由战场统一处理。
/// 组件的 position/scale 仅作渲染用途，由战场按逻辑状态驱动。
class Bullet extends PositionComponent {
  Bullet({
    required this.walls,
    required this.color,
    required Sprite sprite,
    required this.logicalPos,
    required double angle,
  }) {
    // 以组件中心为锚点；priority 同坦克，保证绘制在迷宫之上
    anchor = Anchor.center;
    priority = 1;
    this.angle = angle;
    _direction = Vector2(math.cos(angle), math.sin(angle));

    // 圆形贴图直径约 0.11 格（素材 30px，按车长 135px=0.5 格换算）
    size = Vector2.all(Bullet.radius * 2);
    add(
      SpriteComponent(
        sprite: sprite,
        size: Vector2.all(Bullet.radius * 2),
        paint: Paint()..colorFilter = tintFilter(color),
      ),
    );
  }

  /// 参与碰撞的墙体矩形（迷宫单位，随迷宫生成一次、与画布无关）
  final List<Rect> walls;

  /// 玩家色（子弹染色，同归属坦克）
  final Color color;

  /// 子弹中心在迷宫坐标系下的位置（单位=格）
  Vector2 logicalPos;

  /// 子弹半径（格）：素材 30px，按车长 135px=0.5 格换算
  static const double radius = 15 / 135 * 0.50;

  /// 飞行速度（格/秒）：坦克最大速的 1.2 倍
  static const double _speed = Tank.maxForwardSpeed * 1.2;

  /// 存活时长（秒）：发射 9 秒后消失
  static const double _lifetime = 9.0;

  /// 剩余存活时长
  double _life = _lifetime;

  /// 是否已到寿命（战场据此移除）
  bool get expired => _expired;
  bool _expired = false;

  /// 飞行方向（单位向量）
  late Vector2 _direction;

  /// 移动碰撞子步进上限：与坦克一致，小于墙厚防穿墙
  static const double _maxStep = 0.05;

  @override
  void update(double dt) {
    super.update(dt);
    if (_expired) return;

    _life -= dt;
    if (_life <= 0) {
      _expired = true;
      return;
    }

    // 子步进推进：每步不超过墙厚的一半，撞墙即反弹（不限次数）
    var remaining = _speed * dt;
    while (remaining > 0) {
      final step = math.min(_maxStep, remaining);
      remaining -= step;
      _previousPos = logicalPos;
      logicalPos += _direction * step;
      _bounceOffWalls();
    }
  }

  /// 上一个子步的位置（圆心进入墙内时回退用）
  Vector2 _previousPos = Vector2.zero();

  /// 圆形碰撞体与墙相交时沿墙面法线反射，并推出重叠
  void _bounceOffWalls() {
    for (final wall in walls) {
      final closestX =
          logicalPos.x.clamp(wall.left, wall.right).toDouble();
      final closestY = logicalPos.y.clamp(wall.top, wall.bottom).toDouble();
      final dx = logicalPos.x - closestX;
      final dy = logicalPos.y - closestY;
      final distSq = dx * dx + dy * dy;
      if (distSq >= Bullet.radius * Bullet.radius) continue;

      if (dx == 0 && dy == 0) {
        // 圆心进入墙内（极端情况）：回退上一步并沿速度主导轴反弹
        _reflectDominantAxis();
        logicalPos = _previousPos.clone();
        return;
      }

      final dist = math.sqrt(distSq);
      final nx = dx / dist;
      final ny = dy / dist;
      // 镜面反射：v -= 2(v·n)n
      final dot = _direction.x * nx + _direction.y * ny;
      _direction
        ..x -= 2 * dot * nx
        ..y -= 2 * dot * ny;
      // 推出重叠：贴到墙面外
      logicalPos = Vector2(closestX, closestY) + Vector2(nx, ny) * radius;
    }
  }

  /// 沿速度主导轴反射（法线不可得的兜底）
  void _reflectDominantAxis() {
    if (_direction.x.abs() > _direction.y.abs()) {
      _direction.x = -_direction.x;
    } else {
      _direction.y = -_direction.y;
    }
  }
}
