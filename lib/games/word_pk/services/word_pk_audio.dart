import 'package:horyx/shared/audio/game_audio.dart';

/// 单词PK音效（Kenney Interface Sounds，CC0，经 assets/word_pk/audio/ 打包）。
/// 播放与缓存委托共享门面 [GameAudio]（预解码进内存、多路叠放、失败静默降级）。
/// 触发时机：提交通过→accept（本地提交与联机单词生效均发声）、
/// 提交被拒→reject（本地校验拒绝与联机回执拒绝统一一条）。
/// 对局页 initState 中调 [preload]。
abstract final class WordPkAudio {
  static const String _accept = 'assets/word_pk/audio/accept.ogg';
  static const String _reject = 'assets/word_pk/audio/reject.ogg';

  /// 音效资产路径全集（素材存在性单测逐一校验）
  static const List<String> files = [_accept, _reject];

  static Future<void> preload() => GameAudio.preload(files);

  /// 提交通过
  static void accept() => GameAudio.play(_accept);

  /// 提交被拒
  static void reject() => GameAudio.play(_reject);
}
