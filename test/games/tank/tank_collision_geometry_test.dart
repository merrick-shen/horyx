import 'dart:math';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:horyx/games/tank/game/tank.dart';

/// 坦克 SAT 碰撞几何测试：验证车体/炮管双矩形与墙的相交判定与推出向量
void main() {
  // 与 Tank 构造一致的实测参数（单位=格）
  const hullLength = 0.50;
  const hullWidth = hullLength * 103 / 135;
  const cannonScale = hullWidth * 0.75 / 74;
  const muzzle = (125 - 36.5) * cannonScale;
  final hullHalf = Vector2(hullLength / 2, hullWidth / 2);
  final barrelHalf = Vector2(muzzle / 2, 12.5 * cannonScale);

  // 车体中心在原点、朝右（angle=0）时的碰撞矩形中心
  final hullCenter = Vector2.zero();
  final barrelCenter = Vector2(muzzle / 2, 0);

  group('坦克碰撞几何（SAT）', () {
    test('车体正前方留出炮管伸出量时：车体不碰、炮管碰（双矩形各自生效）', () {
      // 车头前缘在 x=0.25，炮口在 x=muzzle(≈0.34)
      // 墙放 x=0.30 处（厚 0.1）：只与炮管重叠、未及车体
      final wall = Rect.fromCenter(center: const Offset(0.35, 0), width: 0.1, height: 1.0);
      final wallHalf = Vector2(wall.width / 2, wall.height / 2);
      final wallCenter = Vector2(wall.center.dx, wall.center.dy);

      expect(
        Tank.rectsOverlap(hullCenter, 0, hullHalf, wallCenter, 0, wallHalf),
        isFalse,
        reason: '车体矩形不应与炮管前方的墙相交',
      );
      expect(
        Tank.rectsOverlap(barrelCenter, 0, barrelHalf, wallCenter, 0, wallHalf),
        isTrue,
        reason: '炮管矩形应有独立碰撞',
      );
    });

    test('墙贴住车头前缘：车体立即碰撞', () {
      final wall = Rect.fromCenter(center: const Offset(0.28, 0), width: 0.1, height: 1.0);
      final wallHalf = Vector2(wall.width / 2, wall.height / 2);
      final wallCenter = Vector2(wall.center.dx, wall.center.dy);
      expect(
        Tank.rectsOverlap(hullCenter, 0, hullHalf, wallCenter, 0, wallHalf),
        isTrue,
      );
    });

    test('旋转 45° 后炮管斜指墙角：旋转矩形 SAT 仍正确', () {
      // 车体朝右上 45°，炮管指向 (cos45, sin45)*muzzle
      final angle = pi / 4;
      final barrelDir = Vector2(cos(angle), sin(angle));
      final rotatedBarrelCenter = barrelDir * muzzle / 2;
      // 墙放在炮管尖端附近
      final wall = Rect.fromCenter(
        center: Offset(barrelDir.x * muzzle + 0.04, barrelDir.y * muzzle + 0.04),
        width: 0.12,
        height: 0.12,
      );
      final wallHalf = Vector2(wall.width / 2, wall.height / 2);
      final wallCenter = Vector2(wall.center.dx, wall.center.dy);

      expect(
        Tank.rectsOverlap(
          rotatedBarrelCenter, angle, barrelHalf, wallCenter, 0, wallHalf,
        ),
        isTrue,
        reason: '旋转后炮管矩形应与斜前方墙相交',
      );
    });

    test('MTV 推出方向：把矩形 1 推离矩形 2（不重叠时为 null）', () {
      final wall = Rect.fromCenter(center: const Offset(0.30, 0), width: 0.1, height: 1.0);
      final wallHalf = Vector2(wall.width / 2, wall.height / 2);
      final wallCenter = Vector2(wall.center.dx, wall.center.dy);

      final mtv = Tank.rectMtv(barrelCenter, 0, barrelHalf, wallCenter, 0, wallHalf);
      expect(mtv, isNotNull);
      // 墙在 +x 侧，推出方向应为 -x
      expect(mtv!.x, isNegative, reason: '应沿 -x 把炮管推离墙');

      // 相距很远的墙：无接触无推出
      final far = Rect.fromCenter(center: const Offset(3, 0), width: 0.1, height: 1.0);
      final farCenter = Vector2(far.center.dx, far.center.dy);
      expect(
        Tank.rectMtv(barrelCenter, 0, barrelHalf, farCenter, 0, wallHalf),
        isNull,
      );
    });
  });

  group('最短角度差（转向与远程平滑共用）', () {
    test('同向小角度差直接返回', () {
      expect(Tank.angleDelta(0.3, 0.5), closeTo(0.2, 1e-9));
      expect(Tank.angleDelta(0.5, 0.3), closeTo(-0.2, 1e-9));
    });

    test('跨越 ±π 边界时走最短弧', () {
      // 179° → -179°：差 358°，最短弧应为 +2°（跨过 π 而非绕远路）
      expect(Tank.angleDelta(179 * pi / 180, -179 * pi / 180),
          closeTo(2 * pi / 180, 1e-9));
      // 反向同理
      expect(Tank.angleDelta(-179 * pi / 180, 179 * pi / 180),
          closeTo(-2 * pi / 180, 1e-9));
    });

    test('目标角超出 [-π, π]（摇杆 atan2 或 2π 归一后）仍正确', () {
      // 目标 2π - 0.1（等价 -0.1），当前 0.1：应走 -0.2 的短弧
      expect(Tank.angleDelta(0.1, 2 * pi - 0.1), closeTo(-0.2, 1e-9));
    });

    test('相等角度差为零', () {
      expect(Tank.angleDelta(1.23, 1.23), 0);
    });
  });
}
