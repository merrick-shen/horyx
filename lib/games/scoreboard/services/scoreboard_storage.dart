import 'package:horyx/games/scoreboard/models/scoreboard_game_state.dart';
import 'package:horyx/shared/storage/archive_storage.dart';

/// 计分器存档服务（归属标识 + 模型序列化，流程见 ArchiveStorage）
class ScoreboardStorage extends ArchiveStorage<ScoreboardGameState> {
  const ScoreboardStorage();

  /// 全局唯一实例（保持原静态调用习惯：ScoreboardStorage.instance.saveArchive()）
  static const ScoreboardStorage instance = ScoreboardStorage();

  @override
  String get gameId => '计分器';

  @override
  ScoreboardGameState fromJson(Map<String, dynamic> json) =>
      ScoreboardGameState.fromJson(json);

  @override
  Map<String, dynamic> toJson(ScoreboardGameState state) => state.toJson();
}
