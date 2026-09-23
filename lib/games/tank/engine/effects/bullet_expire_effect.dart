import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'package:horyx/games/tank/engine/effects/particle_emitter.dart';

/// 子弹消失消散特效（命中目标或达到射程极限时触发，总时长 0.6 秒）：
/// 一小股黑烟在消失点全向原地散开、缓慢膨胀淡出（俯视视角，不上飘）。
/// [sizeScale] 与爆炸特效一致（pt → 战场像素换算，按坦克体长对齐）。
/// 纯渲染叠加：不参与碰撞、不读写游戏逻辑状态。
class BulletExpireEffect extends Component {
  BulletExpireEffect({
    required Sprite smokeSprite,
    required Vector2 position,
    required double sizeScale,
  }) {
    add(
      ParticleEmitter(
        sprite: smokeSprite,
        position: position,
        count: 5,
        color: const Color(0xFF000000),
        speed: 20,
        speedVariance: 10,
        lifespan: 0.5,
        lifespanVariance: 0.1,
        startSize: 12,
        startSizeVariance: 3,
        finishSize: 16,
        startAlpha: 0.45,
        finishAlpha: 0,
        // 俯视视角：全向原地散开，不指定上飘方向
        angleDeg: 0,
        angleVarianceDeg: 180,
        positionVariance: Vector2.all(2),
        sizeScale: sizeScale,
      ),
    );
  }

  /// 烟雾全部消散后自移除，避免组件残留
  @override
  void update(double dt) {
    super.update(dt);
    if (children.isEmpty) removeFromParent();
  }
}
