import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// 共享音频门面：全项目唯一触达 SoLoud 的地方，各游戏音效经此预载与播放。
/// 基于 SoLoud 引擎：[preload] 将音频预解码进内存（AudioSource），
/// 触发播放延迟毫秒级、支持多路叠放（连发互不截断）。
/// 全程静默降级：初始化/解码失败不抛出，未加载条目播放直接返回，
/// 音效缺失只影响听觉、绝不影响游戏功能。
abstract final class GameAudio {
  /// 已加载的音频（按资产路径索引）；AudioSource 持有原生解码内存，
  /// 一经加载全应用复用，绝不覆盖（覆盖而不 dispose 会泄漏）
  static final Map<String, AudioSource> _sounds = {};

  /// 预载占位任务（按资产路径索引）：putIfAbsent 互斥同路径并发预载，
  /// 防止双载并覆盖先解码的 AudioSource（泄漏）。完成态 Future 复用
  /// 无副作用，条目常驻（量级 = 全部音效资产数，可忽略）
  static final Map<String, Future<void>> _preloading = {};

  /// 预解码音效进内存；已加载条目自动跳过，可安全重复调用。
  /// 引擎初始化失败则整体静默（解码无从谈起）；单条解码失败只跳过该条——
  /// 多游戏共用后，单条素材损坏不应拖垮其余全部音效。
  static Future<void> preload(List<String> assetPaths) async {
    try {
      if (!SoLoud.instance.isInitialized) {
        await SoLoud.instance.init();
      }
    } catch (e) {
      debugPrint('GameAudio 引擎初始化失败，音效静默降级: $e');
      return;
    }
    for (final path in assetPaths) {
      // putIfAbsent 占位互斥：同路径并发 preload 只解码一次，后到者
      // 等待同一 Future（完成后 _sounds 已有条目，播放直接可用）
      await _preloading.putIfAbsent(path, () => _loadOne(path));
    }
  }

  /// 解码单条音效进 [_sounds]；失败只跳过该条
  static Future<void> _loadOne(String path) async {
    if (_sounds.containsKey(path)) return;
    try {
      _sounds[path] = await SoLoud.instance.loadAsset(path);
    } catch (e) {
      debugPrint('GameAudio 预载失败（该条静默）: $path, $e');
    }
  }

  /// 触发播放（fire-and-forget，不阻塞游戏帧）；未加载条目直接返回。
  /// [volume] 供多来源素材响度平衡，默认原声。
  /// SoLoud 运行时异常（如引擎被意外停止）静默降级，与类文档口径一致
  static void play(String assetPath, {double volume = 1.0}) {
    final sound = _sounds[assetPath];
    if (sound == null) return;
    try {
      SoLoud.instance.play(sound, volume: volume);
    } catch (e) {
      debugPrint('GameAudio 播放失败（静默降级）: $assetPath, $e');
    }
  }
}
