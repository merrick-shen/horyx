import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';
import 'package:horyx/shared/storage/archive_storage.dart';

/// 飞行棋对局存档服务（归属标识 + 模型序列化，流程见 ArchiveStorage）
class AeroplaneStorage extends ArchiveStorage<AeroplaneGameState> {
  const AeroplaneStorage();

  /// 全局唯一实例（与其他游戏存档保持同一调用习惯）
  static const AeroplaneStorage instance = AeroplaneStorage();

  @override
  String get gameId => '飞行棋';

  @override
  AeroplaneGameState fromJson(Map<String, dynamic> json) =>
      AeroplaneGameState.fromJson(json);

  @override
  Map<String, dynamic> toJson(AeroplaneGameState state) => state.toJson();
}
