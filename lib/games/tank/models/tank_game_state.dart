/// 坦克动荡对局存档模型
/// 仅保存双方比分——坦克位置、迷宫地图等战场状态不存档，
/// 恢复时重新开一局随机迷宫，从存档比分继续累计
class TankGameState {
  const TankGameState({
    required this.redScore,
    required this.greenScore,
    required this.savedAt,
  });

  /// 红方比分
  final int redScore;

  /// 绿方比分
  final int greenScore;

  /// 存档时间
  final DateTime savedAt;

  /// 数据格式版本号：字段结构变更时递增，便于后续读取旧档时迁移
  /// （与其他游戏存档模型一致；旧存档缺失此字段时视为 1）
  static const int version = 1;

  Map<String, dynamic> toJson() => {
        'version': version,
        'redScore': redScore,
        'greenScore': greenScore,
        'savedAt': savedAt.toIso8601String(),
      };

  factory TankGameState.fromJson(Map<String, dynamic> json) => TankGameState(
        redScore: json['redScore'] as int,
        greenScore: json['greenScore'] as int,
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}
