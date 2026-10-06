import 'package:horyx/shared/audio/game_audio.dart';

/// 五子棋音效（Kenney Casino Audio，CC0，经 assets/gomoku/audio/ 打包）。
/// 播放与缓存委托共享门面 [GameAudio]（预解码进内存、多路叠放、失败静默降级）。
/// 触发时机：确认落子生效→place（本地确认与联机生效广播均发声；
/// 胜利/终局类音效已确认不做）。
/// 对局页 initState 中调 [preload]。
abstract final class GomokuAudio {
  static const String _place = 'assets/gomoku/audio/place.ogg';

  /// 音效资产路径全集（素材存在性单测逐一校验）
  static const List<String> files = [_place];

  static Future<void> preload() => GameAudio.preload(files);

  /// 落子
  static void place() => GameAudio.play(_place);
}
