import 'dart:math';

import 'package:horyx/shared/audio/game_audio.dart';

/// 坦克动荡音效（素材提取自原版 APK 音频，经 assets/tank/audio/ 打包）。
/// 播放与缓存委托共享门面 [GameAudio]（预解码进内存、多路叠放、失败静默降级）。
/// 触发时机：开火→shoot、子弹撞墙→wallBounce（随机两种音色）、
/// 子弹到寿命消失→bulletExpire、坦克被击毁→explosion。
/// 战场 onLoad 中调 [preload]。
abstract final class TankAudio {
  static const String _shoot = 'assets/tank/audio/shoot.ogg';
  static const String _wallBounce0 = 'assets/tank/audio/wall_bounce_0.ogg';
  static const String _wallBounce1 = 'assets/tank/audio/wall_bounce_1.ogg';
  static const String _bulletExpire = 'assets/tank/audio/bullet_expire.ogg';
  static const String _explosion = 'assets/tank/audio/explosion.ogg';

  static const List<String> _files = [
    _shoot,
    _wallBounce0,
    _wallBounce1,
    _bulletExpire,
    _explosion,
  ];

  static Future<void> preload() => GameAudio.preload(_files);

  /// 开火
  static void shoot() => GameAudio.play(_shoot);

  /// 子弹撞墙反弹（两种音色随机，避免重复感）
  static void wallBounce() =>
      GameAudio.play(Random().nextBool() ? _wallBounce0 : _wallBounce1);

  /// 子弹到寿命消失
  static void bulletExpire() => GameAudio.play(_bulletExpire);

  /// 坦克被击毁爆炸
  static void explosion() => GameAudio.play(_explosion);
}
