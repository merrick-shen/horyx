import 'package:horyx/games/chess/models/chess_game_state.dart';
import 'package:horyx/shared/storage/archive_storage.dart';

/// 象棋对局存档服务（存储键 + 模型序列化，流程见 ArchiveStorage）
class ChessStorage extends ArchiveStorage<ChessGameState> {
  const ChessStorage();

  /// 全局唯一实例（与其他游戏存档保持同一调用习惯）
  static const ChessStorage instance = ChessStorage();

  @override
  String get storageKey => 'chess_unfinished_state';

  @override
  String get gameId => '中国象棋';

  @override
  ChessGameState fromJson(Map<String, dynamic> json) =>
      ChessGameState.fromJson(json);

  @override
  Map<String, dynamic> toJson(ChessGameState state) => state.toJson();
}
