import '../../models/games/weiqi_game_state.dart';
import 'archive_storage.dart';

/// 围棋对局存档服务（存储键 + 模型序列化，流程见 ArchiveStorage）
/// 围棋入口暂时下架，本服务保留待恢复入口时复用
class WeiqiStorage extends ArchiveStorage<WeiqiGameState> {
  const WeiqiStorage();

  /// 全局唯一实例（保持原静态调用习惯：WeiqiStorage.instance.load()）
  static const WeiqiStorage instance = WeiqiStorage();

  @override
  String get storageKey => 'weiqi_unfinished_state';

  @override
  WeiqiGameState fromJson(Map<String, dynamic> json) =>
      WeiqiGameState.fromJson(json);

  @override
  Map<String, dynamic> toJson(WeiqiGameState state) => state.toJson();
}
