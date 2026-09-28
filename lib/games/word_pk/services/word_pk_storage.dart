import 'package:horyx/games/word_pk/models/word_pk_game_state.dart';
import 'package:horyx/shared/storage/archive_storage.dart';

/// 单词PK对局存档服务（归属标识 + 模型序列化，流程见 ArchiveStorage）
class WordPkStorage extends ArchiveStorage<WordPkGameState> {
  const WordPkStorage();

  /// 全局唯一实例（保持原静态调用习惯：WordPkStorage.instance.saveArchive()）
  static const WordPkStorage instance = WordPkStorage();

  @override
  String get gameId => '单词PK';

  @override
  WordPkGameState fromJson(Map<String, dynamic> json) =>
      WordPkGameState.fromJson(json);

  @override
  Map<String, dynamic> toJson(WordPkGameState state) => state.toJson();
}
