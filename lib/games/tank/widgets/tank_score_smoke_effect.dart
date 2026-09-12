import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:horyx/games/tank/game/tint_filter.dart';
import 'package:horyx/shared/utils/asset_image.dart';

/// 比分数字烟雾特效（widget 层覆盖层，叠在比分数字上）：
/// [tick] 每次自增立即从数字底部爆出一团黑烟，向上飘散并横向
/// 散开、覆盖整个数字、线性淡出，总时长固定 1 秒（瞬发 + 寿命 1s）。
/// 形态取自坦克动荡 APK 的 Scores Smoke 配置（10 粒上飘），
/// 全部长度参数按数字宽高归一化，且绘制时裁剪到数字自身矩形——
/// 烟雾（含底部出生点）绝不超出数字范围。
/// 纯渲染叠加：不拦截手势、不读写游戏逻辑状态。
class TankScoreSmokeEffect extends StatefulWidget {
  const TankScoreSmokeEffect({super.key, required this.tick});

  /// 触发计数：每次自增爆一团烟雾（0=不触发）
  final int tick;

  @override
  State<TankScoreSmokeEffect> createState() => _TankScoreSmokeEffectState();
}

class _TankScoreSmokeEffectState extends State<TankScoreSmokeEffect>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _last = Duration.zero;
  ui.Image? _smoke;
  final List<_Puff> _puffs = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _loadSmoke();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  /// 复用战场同款烟雾纹理（loadAssetImage 按路径缓存，
  /// 与战场 onLoad 的加载共享同一次解码，不再重复解码）
  Future<void> _loadSmoke() async {
    final image = await loadAssetImage('assets/tank/explosion_smoke.png');
    if (mounted) setState(() => _smoke = image);
  }

  @override
  void didUpdateWidget(TankScoreSmokeEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 数字变化立即爆烟（tick 自增即一次得分）
    if (widget.tick != oldWidget.tick && widget.tick > 0) _burst();
  }

  /// 从数字底部爆出一团黑烟：10 粒聚在底部、向上飘过整个数字并
  /// 横向散开，寿命 1 秒。归一化参数：尺寸 0.28±0.05（相对数字高）、
  /// 横向出生散布 ±0.3 + 漂移 ±0.1（相对数字宽：烟宽随位数等比加宽，
  /// 两位数时烟雾自动更宽）、1 秒上飘 0.7 个数字高（底部出生、
  /// 顶部恰好不越数字上边）
  void _burst() {
    if (_smoke == null) return;
    for (var i = 0; i < 10; i++) {
      final nsize = 0.28 + _var(0.05);
      _puffs.add(
        _Puff(
          nx0: _var(0.3),
          // 底部出生：粒子下缘贴数字底边
          ny0: 0.5 - nsize / 2,
          nvx: _var(0.1),
          nvy: -0.7,
          nsize: nsize,
          alpha0: (0.5 + _var(0.1)).clamp(0.0, 1.0),
        ),
      );
    }
    if (!_ticker!.isActive) _ticker!.start();
  }

  /// [-v, v] 均匀随机
  double _var(double v) => v == 0 ? 0 : (_random.nextDouble() * 2 - 1) * v;

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    setState(() {
      _puffs.removeWhere((p) {
        p.life -= dt;
        return p.life <= 0;
      });
    });
    // 全部消散后停表，避免空转重绘
    if (_puffs.isEmpty) {
      _ticker!.stop();
      _last = Duration.zero;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(painter: _PuffPainter(_puffs, _smoke)),
    );
  }
}

/// 绘制全部烟粒：以数字中心为原点，位置/尺寸按数字高度换算，线性淡出
class _PuffPainter extends CustomPainter {
  _PuffPainter(this.puffs, this.image);

  final List<_Puff> puffs;
  final ui.Image? image;

  /// 黑烟染色（白模纹理按通道缩为黑），透明度走 Paint.color 的 Alpha
  static final Paint _paint = Paint()
    ..colorFilter = tintFilter(const Color(0xFF000000));

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img == null || puffs.isEmpty) return;
    // 硬约束：烟雾（含底部出生点）只在数字自身矩形内绘制，越界裁剪
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, size.height));
    final center = size.center(Offset.zero);
    final src =
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    for (final p in puffs) {
      // 寿命固定 1 秒：已过时长即 1-life；横向按数字宽、纵向按数字高换算
      final t = 1 - p.life;
      final alpha = (p.alpha0 * p.life).clamp(0.0, 1.0);
      _paint.color = Color.fromARGB((alpha * 255).round(), 255, 255, 255);
      canvas.drawImageRect(
        img,
        src,
        Rect.fromCenter(
          center: center +
              Offset((p.nx0 + p.nvx * t) * size.width,
                  (p.ny0 + p.nvy * t) * size.height),
          width: p.nsize * size.height,
          height: p.nsize * size.height,
        ),
        _paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PuffPainter oldDelegate) => true;
}

/// 单个烟粒运行时状态（全部长度按数字高度归一化）
class _Puff {
  _Puff({
    required this.nx0,
    required this.ny0,
    required this.nvx,
    required this.nvy,
    required this.nsize,
    required this.alpha0,
  });

  /// 出生散布（nx0 相对数字宽、ny0 相对数字高）
  final double nx0;
  final double ny0;

  /// 速度（每秒位移，nvx 相对数字宽、nvy 相对数字高）
  final double nvx;
  final double nvy;

  /// 粒子尺寸（相对数字高）
  final double nsize;
  final double alpha0;

  /// 剩余寿命（秒，固定 1 秒）
  double life = 1.0;
}
