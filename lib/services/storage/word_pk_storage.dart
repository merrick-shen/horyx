import '../../models/games/word_pk_game_state.dart';
import 'archive_storage.dart';

/// 单词PK对局存档服务（存储键 + 模型序列化，流程见 ArchiveStorage）
class WordPkStorage extends ArchiveStorage<WordPkGameState> {
  const WordPkStorage();

  /// 全局唯一实例（保持原静态调用习惯：WordPkStorage.instance.load()）
  static const WordPkStorage instance = WordPkStorage();

  @override
  String get storageKey => 'word_pk_unfinished_state';

  @override
  WordPkGameState fromJson(Map<String, dynamic> json) =>
      WordPkGameState.fromJson(json);

  @override
  Map<String, dynamic> toJson(WordPkGameState state) => state.toJson();
}
