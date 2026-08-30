import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'package:horyx/games/tank/models/tank_player.dart';

/// 瞬发粒子发射器（Cocos2d 重力模式粒子语义，参数以视觉效果调优为准）。
/// 挂载即一次性爆出 [count] 个粒子：各粒子按发射角±随机幅定向、速度/尺寸/寿命随机，
/// 每帧积分速度+重力（cocos y 向上，已换算为 Flutter y 向下），
/// 尺寸与透明度按寿命线性插值，全部粒子过期后自移除。
/// 长度类参数（速度/重力/尺寸/散布）统一乘 [sizeScale]：素材坐标空间约 320pt 宽，
/// 本战场像素尺度不同，须按坦克体长比例换算才能保持观感一致。
/// 染色走 [tintFilter]（白模纹理按通道缩放）：Paint.color 的 RGB 对贴图无染色作用，
/// 仅 Alpha 用于透明度渐变。纯渲染叠加：不参与碰撞、不读写游戏逻辑状态。
class ParticleEmitter extends PositionComponent {
  ParticleEmitter({
    required this.sprite,
    required Vector2 position,
    required this.count,
    required this.color,
    required this.speed,
    this.speedVariance = 0,
    required this.lifespan,
    this.lifespanVariance = 0,
    required this.startSize,
    this.startSizeVariance = 0,
    required this.finishSize,
    required this.startAlpha,
    this.startAlphaVariance = 0,
    this.finishAlpha = 0,
    this.gravity = 0,
    this.radialAccel = 0,
    this.spinDeg = 0,
    this.angleDeg = 0,
    this.angleVarianceDeg = 180,
    Vector2? positionVariance,
    this.sizeScale = 1,
    this.trailSprite,
    this.trailColor = const Color(0xFF000000),
    this.trailRate = 0,
    this.trailStartSize = 9,
    this.trailFinishSize = 16,
    this.trailLife = 0.7,
    this.trailAlpha = 0.35,
    this.hitTest,
    this.fadeExp = 1,
  })  : positionVariance = positionVariance ?? Vector2.zero(),
        // priority 高于坦克/子弹（1）：特效叠加在战场实体之上
        super(position: position, priority: 2) {
    _paint.colorFilter = tintFilter(color);
    _spawn();
  }

  final Sprite sprite;
  final math.Random _random = math.Random();

  /// 粒子数量
  final int count;

  /// 粒子染色（白模纹理经 tintFilter 缩放为该色：黑=烟雾/碎片）
  final Color color;

  /// 初速与随机幅（pt/秒，渲染时乘 sizeScale）
  final double speed;
  final double speedVariance;

  /// 寿命与随机幅（秒）
  final double lifespan;
  final double lifespanVariance;

  /// 初/末尺寸（pt，渲染时乘 sizeScale）
  final double startSize;
  final double startSizeVariance;
  final double finishSize;

  /// 初/末透明度
  final double startAlpha;
  final double startAlphaVariance;
  final double finishAlpha;

  /// 纵向重力（pt/秒²，cocos y 向上；渲染时反向并乘 sizeScale）
  final double gravity;

  /// 径向加速度（pt/秒²，沿爆点向外的方向加速；负值=向外飞出后减速，
  final double radialAccel;

  /// 粒子自旋总量（度，寿命内随机正负方向转完；0=不旋转）
  final double spinDeg;

  /// 发射角与随机幅（度，cocos 语义：0=右、90=上；variance=180 即全向）
  final double angleDeg;
  final double angleVarianceDeg;

  /// 出生点散布半径（pt，渲染时乘 sizeScale）
  final Vector2 positionVariance;

  /// pt → 本战场像素换算比例（按坦克体长对齐）
  final double sizeScale;

  /// 拖尾烟雾纹理（非空时：每个存活主粒子每秒按 [trailRate] 概率
  /// 在当前位置留下一粒小烟，形成"碎片跟着出烟"的尾迹）
  final Sprite? trailSprite;

  /// 拖尾烟雾颜色（黑烟）
  final Color trailColor;

  /// 每粒主粒子每秒生成拖尾的期望次数
  final double trailRate;

  /// 拖尾初/末尺寸（pt，乘 sizeScale）与寿命（秒）、初透明度
  final double trailStartSize;
  final double trailFinishSize;
  final double trailLife;
  final double trailAlpha;

  /// 墙体碰撞查询（屏幕坐标 → 是否撞墙）。粒子下一位置撞墙则
  /// 速度归零、原地停住，仅做缓慢淡出（残骸贴墙感）
  final bool Function(Vector2 screenPos)? hitTest;

  /// 淡出曲线指数：透明度按 pow(t, fadeExp) 推进，>1 时前段保持
  /// 可见、后段才消散（"缓慢消失"不空）；1=线性
  final double fadeExp;

  final List<_Particle> _particles = [];
  final List<_Particle> _trails = [];
  final Paint _paint = Paint();
  Paint? _trailPaint;

  /// 挂载即爆出全部粒子（瞬发）
  void _spawn() {
    for (var i = 0; i < count; i++) {
      final ang = (angleDeg + _var(angleVarianceDeg)) * math.pi / 180;
      final sp = (speed + _var(speedVariance)) * sizeScale;
      final life = (lifespan + _var(lifespanVariance)).clamp(0.05, 60.0);
      _particles.add(
        _Particle(
          x: _var(positionVariance.x) * sizeScale,
          y: _var(positionVariance.y) * sizeScale,
          vx: math.cos(ang) * sp,
          // cocos y 向上 → Flutter y 向下
          vy: -math.sin(ang) * sp,
          rx: math.cos(ang),
          ry: -math.sin(ang),
          life: life,
          totalLife: life,
          // 尺寸下限 2：±variance 可能取到近零值，过小粒子无视觉意义
          size0: (startSize + _var(startSizeVariance)).clamp(2.0, 512.0) *
              sizeScale,
          alpha0: (startAlpha + _var(startAlphaVariance)).clamp(0.0, 1.0),
          rot: spinDeg == 0
              ? 0
              : (_random.nextBool() ? 1 : -1) * spinDeg * math.pi / 180,
          stopped: false,
        ),
      );
    }
  }

  /// [-v, v] 均匀随机
  double _var(double v) => v == 0 ? 0 : (_random.nextDouble() * 2 - 1) * v;

  @override
  void update(double dt) {
    _particles.removeWhere((p) {
      p.life -= dt;
      if (p.life <= 0) return true;
      if (!p.stopped) {
        // cocos 重力 y 向上 → Flutter 向下取反
        p.vy -= gravity * sizeScale * dt;
        // 径向加速度沿爆点向外方向（负值=向外减速）。
        // 只在仍向外运动时施加；减速到零即原地停驻——
        // 若继续施加，速度反向会让碎片在空中"反弹回爆心"
        final vr = p.vx * p.rx + p.vy * p.ry;
        if (radialAccel != 0 && vr > 0) {
          p.vx += p.rx * radialAccel * sizeScale * dt;
          p.vy += p.ry * radialAccel * sizeScale * dt;
          if (p.vx * p.rx + p.vy * p.ry <= 0) {
            p.vx = 0;
            p.vy = 0;
            p.stopped = true;
          }
        }
        final nx = p.x + p.vx * dt;
        final ny = p.y + p.vy * dt;
        final test = hitTest;
        if (test != null &&
            test(position + Vector2(nx, ny))) {
          // 撞墙：速度归零、原地停住，仅做缓慢淡出（残骸贴墙感）
          p.vx = 0;
          p.vy = 0;
          p.stopped = true;
        } else {
          p.x = nx;
          p.y = ny;
        }
      }
      // 拖尾：飞行中按 trailRate 留烟；停住后按较低概率续余烟，
      // 避免碎片停下后烟雾突兀断档
      final rate = p.stopped ? trailRate * 0.3 : trailRate;
      if (trailSprite != null && _random.nextDouble() < rate * dt) {
        _trails.add(
          _Particle(
            x: p.x,
            y: p.y,
            vx: 0,
            vy: 0,
            rx: 0,
            ry: 0,
            life: trailLife,
            totalLife: trailLife,
            size0: trailStartSize * sizeScale,
            alpha0: trailAlpha,
            rot: 0,
            stopped: false,
          ),
        );
      }
      return false;
    });
    _trails.removeWhere((p) {
      p.life -= dt;
      return p.life <= 0;
    });
    if (_particles.isEmpty && _trails.isEmpty) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final image = sprite.image;
    final src =
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    for (final p in _particles) {
      final t = 1 - p.life / p.totalLife;
      final size = (p.size0 + (finishSize * sizeScale - p.size0) * t)
          .clamp(1.0, 1024.0);
      // 慢淡出曲线：前段保持可见、后段才消散
      final alpha =
          (p.alpha0 + (finishAlpha - p.alpha0) * math.pow(t, fadeExp))
              .clamp(0.0, 1.0);
      _paint.color = Color.fromARGB((alpha * 255).round(), 255, 255, 255);
      if (p.rot == 0) {
        canvas.drawImageRect(
          image,
          src,
          Rect.fromCenter(
              center: Offset(p.x, p.y), width: size, height: size),
          _paint,
        );
      } else {
        // 自旋：绕粒子中心旋转后绘制
        canvas.save();
        canvas.translate(p.x, p.y);
        canvas.rotate(p.rot * t);
        canvas.drawImageRect(
          image,
          src,
          Rect.fromCenter(center: Offset.zero, width: size, height: size),
          _paint,
        );
        canvas.restore();
      }
    }
    // 拖尾小烟：缓慢膨胀、淡出
    final trail = trailSprite;
    if (trail != null && _trails.isNotEmpty) {
      _trailPaint ??= Paint()..colorFilter = tintFilter(trailColor);
      final tImage = trail.image;
      final tSrc = Rect.fromLTWH(
          0, 0, tImage.width.toDouble(), tImage.height.toDouble());
      for (final p in _trails) {
        final t = 1 - p.life / p.totalLife;
        final size = (p.size0 + (trailFinishSize * sizeScale - p.size0) * t)
            .clamp(1.0, 1024.0);
        final alpha = (p.alpha0 * (1 - math.pow(t, 1.6))).clamp(0.0, 1.0);
        _trailPaint!.color =
            Color.fromARGB((alpha * 255).round(), 255, 255, 255);
        canvas.drawImageRect(
          tImage,
          tSrc,
          Rect.fromCenter(center: Offset(p.x, p.y), width: size, height: size),
          _trailPaint!,
        );
      }
    }
  }
}

/// 单个粒子运行时状态（偏移相对发射器原点，像素）
class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.rx,
    required this.ry,
    required this.life,
    required this.totalLife,
    required this.size0,
    required this.alpha0,
    required this.rot,
    required this.stopped,
  });

  double x;
  double y;
  double vx;
  double vy;

  /// 爆点向外单位方向（径向加速度用）
  final double rx;
  final double ry;
  double life;
  final double totalLife;
  final double size0;
  final double alpha0;

  /// 寿命内自旋总量（弧度，含随机方向；0=不旋转）
  final double rot;

  /// 是否已撞墙停住（停住后不再位移，仅缓慢淡出）
  bool stopped;
}
