import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'package:horyx/games/tank/game/effects/particle_emitter.dart';

/// 坦克被击中爆炸特效（"碎片拖尾 + 撞墙残骸"模型，素材提取自坦克动荡 APK）。
/// 整体时长上限 3 秒：
/// - 三角碎片层：染受害者色残片向外炸开，每粒大小/角度/距离各异、
///   带自旋，飞行沿途留下一串小烟；撞墙或减速到零即停、原地缓慢
///   淡出（寿命 1.8±0.2s，前段保持可见、后段才消散）；
/// - 拖尾小烟：跟着碎片出现、数量多，寿命 1.0s（最后一批尾烟在碎片
///   死亡瞬间生成，消散到 3.0s 上限，比碎片消失得慢）；
/// - 中心大烟层：少量黑烟在爆点快速闪现消散（约 0.5s），不驻留；
/// - 爆闪层：白色闪光全向爆出、快速淡出。
/// [sizeScale] 把 pt 参数换算为本战场像素（素材中坦克体长 48pt 对齐 _cell），
/// 保证不同屏幕尺寸下特效与坦克的比例一致。
/// [hitTest] 为墙体碰撞查询（屏幕坐标 → 是否撞墙），由战场注入；
/// 纯渲染叠加，不改变子弹/坦克的碰撞逻辑。
class TankExplosionEffect extends Component {
  TankExplosionEffect({
    required Sprite shardSprite,
    required Sprite smokeSprite,
    required Sprite flashSprite,
    required Vector2 position,
    required Color color,
    required this.sizeScale,
    this.hitTest,
  }) {
    // 三角碎片层：全向炸开、大小/速度高方差、自旋、负径向加速度减速，
    // 撞墙停住后原地缓慢淡出，沿途留小烟尾迹
    add(
      ParticleEmitter(
        sprite: shardSprite,
        position: position,
        count: 12,
        color: color,
        speed: 130,
        speedVariance: 80,
        lifespan: 1.8,
        lifespanVariance: 0.2,
        startSize: 14,
        startSizeVariance: 8,
        finishSize: 10,
        startAlpha: 1,
        finishAlpha: 0,
        fadeExp: 2.5,
        radialAccel: -260,
        spinDeg: 540,
        positionVariance: Vector2.all(4),
        sizeScale: sizeScale,
        hitTest: hitTest,
        trailSprite: smokeSprite,
        trailRate: 12,
        trailStartSize: 8,
        trailFinishSize: 14,
        trailLife: 1.0,
        trailAlpha: 0.35,
      ),
    );
    // 中心大烟层：少量黑烟在爆点快速闪现消散，不驻留
    add(
      ParticleEmitter(
        sprite: smokeSprite,
        position: position,
        count: 3,
        color: const Color(0xFF000000),
        speed: 10,
        speedVariance: 6,
        lifespan: 0.45,
        lifespanVariance: 0.15,
        startSize: 26,
        startSizeVariance: 6,
        finishSize: 34,
        startAlpha: 0.5,
        startAlphaVariance: 0.15,
        finishAlpha: 0,
        positionVariance: Vector2.all(4),
        sizeScale: sizeScale,
      ),
    );
    // 爆闪层：白色闪光全向爆出、快速消散
    add(
      ParticleEmitter(
        sprite: flashSprite,
        position: position,
        count: 12,
        color: const Color(0xFFFFFFFF),
        speed: 30,
        speedVariance: 25,
        lifespan: 0.5,
        lifespanVariance: 0.2,
        startSize: 20,
        startSizeVariance: 10,
        finishSize: 32,
        startAlpha: 0.7,
        startAlphaVariance: 0.2,
        finishAlpha: 0,
        positionVariance: Vector2.all(7),
        sizeScale: sizeScale,
      ),
    );
  }

  /// pt → 本战场像素换算比例（战场按坦克体长传入）
  final double sizeScale;

  /// 墙体碰撞查询（屏幕坐标 → 是否撞墙），可为空（空则碎片不撞墙）
  final bool Function(Vector2 screenPos)? hitTest;

  /// 三层粒子（含拖尾）全部消散后自移除，避免组件残留
  @override
  void update(double dt) {
    super.update(dt);
    if (children.isEmpty) removeFromParent();
  }
}
