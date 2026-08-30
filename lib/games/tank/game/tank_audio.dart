import 'dart:math';

import 'package:flutter_soloud/flutter_soloud.dart';

/// 坦克动荡音效（素材提取自原版 APK 音频，经 assets/tank/audio/ 打包）。
/// 基于 Soloud 引擎：[preload] 将音频预解码进内存（AudioSource），
/// 触发播放延迟毫秒级、支持多路叠放（连发互不截断），与动画同步。
/// 触发时机：开火→shoot、子弹撞墙→wallBounce（随机两种音色）、
/// 子弹到寿命消失→bulletExpire、坦克被击毁→explosion。
/// 战场 onLoad 中调 [preload]（内部完成引擎初始化与音频加载）。
abstract final class TankAudio {
  static const String _prefix = 'assets/tank/audio/';

  static const String _shoot = 'shoot.ogg';
  static const String _wallBounce0 = 'wall_bounce_0.ogg';
  static const String _wallBounce1 = 'wall_bounce_1.ogg';
  static const String _bulletExpire = 'bullet_expire.ogg';
  static const String _explosion = 'explosion.ogg';

  static const List<String> _files = [
    _shoot,
    _wallBounce0,
    _wallBounce1,
    _bulletExpire,
    _explosion,
  ];

  /// 已加载的音频（按文件索引）
  static final Map<String, AudioSource> _sounds = {};

  /// 初始化引擎并预解码全部音效进内存（战场 onLoad 中等待一次）
  static Future<void> preload() async {
    if (!SoLoud.instance.isInitialized) {
      await SoLoud.instance.init();
    }
    for (final file in _files) {
      _sounds[file] = await SoLoud.instance.loadAsset('$_prefix$file');
    }
  }

  /// 触发播放（fire-and-forget，不阻塞游戏帧）
  static void _play(String file) {
    final sound = _sounds[file];
    if (sound == null) return;
    SoLoud.instance.play(sound);
  }

  /// 开火
  static void shoot() => _play(_shoot);

  /// 子弹撞墙反弹（两种音色随机，避免重复感）
  static void wallBounce() =>
      _play(Random().nextBool() ? _wallBounce0 : _wallBounce1);

  /// 子弹到寿命消失
  static void bulletExpire() => _play(_bulletExpire);

  /// 坦克被击毁爆炸
  static void explosion() => _play(_explosion);
}
