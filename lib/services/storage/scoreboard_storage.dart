import '../../models/games/scoreboard_game_state.dart';
import 'archive_storage.dart';

/// 计分器存档服务（存储键 + 模型序列化，流程见 ArchiveStorage）
class ScoreboardStorage extends ArchiveStorage<ScoreboardGameState> {
  const ScoreboardStorage();

  /// 全局唯一实例（保持原静态调用习惯：ScoreboardStorage.instance.load()）
  static const ScoreboardStorage instance = ScoreboardStorage();

  @override
  String get storageKey => 'scoreboard_unfinished_state';

  @override
  ScoreboardGameState fromJson(Map<String, dynamic> json) =>
      ScoreboardGameState.fromJson(json);

  @override
  Map<String, dynamic> toJson(ScoreboardGameState state) => state.toJson();
}
