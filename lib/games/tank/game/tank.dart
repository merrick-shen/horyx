import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'package:horyx/games/tank/models/tank_player.dart';

/// 顶视坦克实体：车体与炮塔随朝向整体旋转，原版摇杆驾驶。
/// 状态存于迷宫坐标系（[logicalPos] 单位=格，原点迷宫左上角），
/// 与画布尺寸无关——前后台切换/窗口变化触发画布重建时，
/// 战场只需按新尺寸重新换算渲染坐标，坦克位置与朝向不丢失。
/// 操控语义（与原版一致）：始终朝摇杆指向旋转（走最短方向），
/// 圆钮推出底座边界后同时沿当前朝向前进（转向中前进走弧线），
/// 前进速度随摇杆超出幅度线性增大（模拟油门，[_forwardSpeed] 为上限）。
/// 碰撞形状与视觉一致：车体矩形 + 炮管矩形（迷宫单位，随朝向旋转），
/// 与墙做 SAT 精确相交测试；移动子步进、撞墙即停；
/// 旋转穿墙沿最小穿透方向弹开（_depenetrate）。
/// 组件的 position/scale 仅作渲染用途，由战场按逻辑状态驱动。
class Tank extends PositionComponent {
  Tank({
    required this.walls,
    required this.color,
    required Sprite bodySprite,
    required Sprite cannonSprite,
    required this.logicalPos,
    required double angle,
  }) {
    // 以组件中心为锚点：渲染时 position 即坦克中心，旋转绕车体中心。
    // priority 高于迷宫组件（默认 0）：迷宫重建（前后台切换触发画布
    // 尺寸变化）会重新添加到渲染队列末尾，坦克必须始终绘制在其之上
    anchor = Anchor.center;
    priority = 1;
    this.angle = angle;

    // 车体长 0.5 格（参考原版车长/通道比例），
    // 其余尺寸按素材比例换算（素材 0° 朝右，单位=格）：
    // 车体素材 135×103；炮塔素材（Bullet0 裁边后）125×74（圆顶中心 36.5,37）。
    // 炮塔缩放按原版截图实测：圆顶直径 ≈ 车宽 75%，
    // 此时炮管伸出车头 ≈ 车长 24%、炮管厚 ≈ 车宽 26%，均与参考图吻合
    const hullLength = 0.50;
    final hullWidth = hullLength * 103 / 135;
    final cannonScale = hullWidth * 0.75 / 74;
    size = Vector2(hullLength, hullWidth);

    // 车体铺满容器；炮塔图圆顶中心对齐车体中心
    add(
      SpriteComponent(
        sprite: bodySprite,
        size: Vector2(hullLength, hullWidth),
        paint: Paint()..colorFilter = tintFilter(color),
      ),
    );
    add(
      SpriteComponent(
        sprite: cannonSprite,
        size: Vector2(125 * cannonScale, 74 * cannonScale),
        position: Vector2(
          hullLength / 2 - 36.5 * cannonScale,
          hullWidth / 2 - 37 * cannonScale,
        ),
        paint: Paint()..colorFilter = tintFilter(color),
      ),
    );

    // 碰撞矩形（车体中心局部坐标）：车体矩形 + 炮管矩形
    // （圆顶中心到炮口，宽取炮管厚）
    final muzzle = (125 - 36.5) * cannonScale;
    _collisionRects = [
      (Vector2.zero(), Vector2(hullLength / 2, hullWidth / 2)),
      (
        Vector2(muzzle / 2, 0),
        Vector2(muzzle / 2, 12.5 * cannonScale),
      ),
    ];
  }

  /// 参与碰撞的墙体矩形（迷宫单位，随迷宫生成一次、与画布无关）
  final List<Rect> walls;

  /// 玩家色（同时用于与对局页摇杆的归属映射）
  final Color color;

  /// 坦克中心在迷宫坐标系下的位置（单位=格）
  Vector2 logicalPos;

  /// 对方坦克：互相视为实体障碍，与墙同等参与碰撞
  Tank? opponent;

  /// 碰撞矩形列表（车体中心局部坐标）：(中心偏移, 半长半宽)
  late final List<(Vector2 offset, Vector2 half)> _collisionRects;

  /// 摇杆驾驶输入；null 表示摇杆回中（停车）
  TankDriveInput? input;

  /// 最大前进速度（格/秒）：实际速度 = 上限 × 摇杆油门（0~1）
  static const double _forwardSpeed = 2.6;

  /// 转向速度（弧度/秒）：原版转向极快，近乎指向即达
  static const double _turnSpeed = 18.0;

  /// 移动碰撞子步进上限：墙厚约 0.1 格，步长须小于墙厚防穿墙
  static const double _maxStep = 0.05;

  /// 旋转子步进：每步不超过 3.4°，旋转导致的穿墙沿最小穿透方向弹开
  static const double _maxTurnStep = 0.06;

  @override
  void update(double dt) {
    super.update(dt);
    final drive = input;
    if (drive == null) return;

    // 朝摇杆指向旋转（走最短方向）；角度差小于本帧转向量时直接对齐。
    // 旋转同样参与碰撞：任一角度步导致穿墙则沿最小穿透方向弹开
    final diff = _angleDelta(drive.targetAngle);
    final maxTurn = _turnSpeed * dt;
    final turn = diff.abs() <= maxTurn ? diff : maxTurn * (diff > 0 ? 1 : -1);
    _turn(turn);

    // 圆钮推出底座边界：沿当前朝向前进，油门（超出幅度）决定速度
    if (drive.speedFactor > 0) {
      _move(_forwardSpeed * drive.speedFactor * dt);
    }
  }

  /// 当前朝向到目标角的最短角度差（-π..π）
  double _angleDelta(double target) {
    var diff = (target - angle) % (2 * math.pi);
    if (diff > math.pi) diff -= 2 * math.pi;
    if (diff < -math.pi) diff += 2 * math.pi;
    return diff;
  }

  /// 旋转 delta（弧度，带符号）：按子步进旋转，每步做穿墙解除
  void _turn(double delta) {
    var applied = 0.0;
    while (applied.abs() < delta.abs()) {
      final step = (delta - applied).clamp(-_maxTurnStep, _maxTurnStep)
          .toDouble();
      angle += step;
      applied += step;
      _depenetrate();
    }
  }

  /// 沿当前朝向移动 distance：按子步进推进，任一步撞墙/撞对方则停在接触前
  void _move(double distance) {
    final direction = Vector2(math.cos(angle), math.sin(angle));
    var travelled = 0.0;
    while (travelled.abs() < distance.abs()) {
      final step = (distance - travelled).clamp(-_maxStep, _maxStep)
          .toDouble();
      final next = logicalPos + direction * step;
      if (_collides(next, angle)) return;
      logicalPos = next;
      travelled += step;
    }
  }

  /// 任一碰撞矩形与墙或对方坦克相交即为碰撞
  bool _collides(Vector2 center, double angle) {
    for (final (offset, half) in _collisionRects) {
      final rectCenter = _localToWorld(center, angle, offset);

      // 墙（轴对齐矩形 = 旋转角为 0 的矩形）
      for (final wall in walls) {
        if (rectsOverlap(
          rectCenter,
          angle,
          half,
          Vector2(wall.center.dx, wall.center.dy),
          0,
          Vector2(wall.width / 2, wall.height / 2),
        )) {
          return true;
        }
      }

      // 对方坦克的碰撞矩形
      final opp = opponent;
      if (opp != null) {
        for (final (oOffset, oHalf) in opp._collisionRects) {
          if (rectsOverlap(
            rectCenter,
            angle,
            half,
            _localToWorld(opp.logicalPos, opp.angle, oOffset),
            opp.angle,
            oHalf,
          )) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// 解除车体与墙/对方的重叠：对所有相交的碰撞矩形，
  /// 沿各自最小穿透方向推出；墙角处一次推离可能顶到别的障碍，迭代 3 次收敛
  void _depenetrate() {
    for (var i = 0; i < 3; i++) {
      var pushed = false;
      for (final (offset, half) in _collisionRects) {
        final rectCenter = _localToWorld(logicalPos, angle, offset);

        for (final wall in walls) {
          final mtv = rectMtv(
            rectCenter,
            angle,
            half,
            Vector2(wall.center.dx, wall.center.dy),
            0,
            Vector2(wall.width / 2, wall.height / 2),
          );
          if (mtv != null) {
            logicalPos += mtv;
            pushed = true;
          }
        }

        final opp = opponent;
        if (opp != null) {
          for (final (oOffset, oHalf) in opp._collisionRects) {
            final mtv = rectMtv(
              rectCenter,
              angle,
              half,
              _localToWorld(opp.logicalPos, opp.angle, oOffset),
              opp.angle,
              oHalf,
            );
            if (mtv != null) {
              logicalPos += mtv;
              pushed = true;
            }
          }
        }
      }
      if (!pushed) break;
    }
  }

  /// 局部偏移（车体中心系）按朝向旋转到目标坐标系
  Vector2 _localToWorld(Vector2 origin, double angle, Vector2 local) {
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    return origin +
        Vector2(
          local.x * cosA - local.y * sinA,
          local.x * sinA + local.y * cosA,
        );
  }

  /// 两个旋转矩形的 SAT 分离轴测试：候选轴为两矩形各自的局部轴，
  /// 任一轴上投影不重叠即不相交
  static bool rectsOverlap(
    Vector2 c1,
    double a1,
    Vector2 half1,
    Vector2 c2,
    double a2,
    Vector2 half2,
  ) {
    final dx = c2.x - c1.x;
    final dy = c2.y - c1.y;
    for (final (ax, ay) in _satAxisList(a1, a2)) {
      final r1 = _projRadius(a1, half1, ax, ay);
      final r2 = _projRadius(a2, half2, ax, ay);
      if ((dx * ax + dy * ay).abs() > r1 + r2) return false;
    }
    return true;
  }

  /// 矩形 1 相对矩形 2 的最小平移向量（把 1 推离 2）；未相交返回 null。
  /// SAT 四轴中最小重叠轴即为推出方向（与中心差方向相反）
  static Vector2? rectMtv(
    Vector2 c1,
    double a1,
    Vector2 half1,
    Vector2 c2,
    double a2,
    Vector2 half2,
  ) {
    final dx = c2.x - c1.x;
    final dy = c2.y - c1.y;

    var bestOverlap = double.infinity;
    var bestX = 0.0;
    var bestY = 0.0;
    for (final (ax, ay) in _satAxisList(a1, a2)) {
      final dot = dx * ax + dy * ay;
      final overlap = _projRadius(a1, half1, ax, ay) +
          _projRadius(a2, half2, ax, ay) -
          dot.abs();
      if (overlap <= 0) return null;
      if (overlap < bestOverlap) {
        bestOverlap = overlap;
        final sign = dot > 0 ? -1.0 : 1.0;
        bestX = ax * overlap * sign;
        bestY = ay * overlap * sign;
      }
    }
    return Vector2(bestX, bestY);
  }

  /// SAT 候选轴：两矩形各自的局部轴（长轴、宽轴）
  static List<(double, double)> _satAxisList(double a1, double a2) {
    return [
      (math.cos(a1), math.sin(a1)),
      (-math.sin(a1), math.cos(a1)),
      (math.cos(a2), math.sin(a2)),
      (-math.sin(a2), math.cos(a2)),
    ];
  }

  /// 旋转矩形（朝向 angle、半尺寸 half）在测试轴 (ax, ay) 上的投影半径：
  /// = half.x*|u·k| + half.y*|v·k|，u/v 为矩形局部轴。
  /// 注意不能用 half.x*|ax| + half.y*|ay|——那是轴对齐盒的公式，
  /// 用在旋转矩形上会把长轴算成短轴（坦克朝上下时穿墙的根源）
  static double _projRadius(double angle, Vector2 half, double ax, double ay) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return half.x * (c * ax + s * ay).abs() +
        half.y * (-s * ax + c * ay).abs();
  }
}
