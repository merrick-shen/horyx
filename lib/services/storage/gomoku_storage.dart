import '../../models/games/gomoku_game_state.dart';
import 'archive_storage.dart';

/// 五子棋对局存档服务（存储键 + 模型序列化，流程见 ArchiveStorage）
class GomokuStorage extends ArchiveStorage<GomokuGameState> {
  const GomokuStorage();

  /// 全局唯一实例（保持原静态调用习惯：GomokuStorage.instance.load()）
  static const GomokuStorage instance = GomokuStorage();

  @override
  String get storageKey => 'gomoku_unfinished_state';

  @override
  GomokuGameState fromJson(Map<String, dynamic> json) =>
      GomokuGameState.fromJson(json);

  @override
  Map<String, dynamic> toJson(GomokuGameState state) => state.toJson();
}
