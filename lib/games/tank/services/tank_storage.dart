import 'package:horyx/games/tank/models/tank_game_state.dart';
import 'package:horyx/shared/storage/archive_storage.dart';

/// 坦克动荡存档服务（存储键 + 模型序列化，流程见 ArchiveStorage）
class TankStorage extends ArchiveStorage<TankGameState> {
  const TankStorage();

  /// 全局唯一实例（保持各游戏静态调用习惯：TankStorage.instance.load()）
  static const TankStorage instance = TankStorage();

  @override
  String get storageKey => 'tank_unfinished_state';

  @override
  TankGameState fromJson(Map<String, dynamic> json) =>
      TankGameState.fromJson(json);

  @override
  Map<String, dynamic> toJson(TankGameState state) => state.toJson();
}
