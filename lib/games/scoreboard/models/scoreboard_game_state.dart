/// 计分器对局存档模型
/// 记录完整计分配置、当前比分与撤销快照栈，用于「保存并退出」后的恢复
class ScoreboardGameState {
  const ScoreboardGameState({
    required this.bestOf,
    required this.winScore,
    required this.leadBy,
    required this.redGames,
    required this.blueGames,
    required this.redScore,
    required this.blueScore,
    required this.history,
    required this.gameOver,
    required this.savedAt,
  });

  /// 赛制（BO 几）
  final int bestOf;

  /// 每局胜利比分
  final int winScore;

  /// 领先获胜分差
  final int leadBy;

  /// 红方已获胜局数（大比分）
  final int redGames;

  /// 蓝方已获胜局数（大比分）
  final int blueGames;

  /// 红方当前局得分（小比分）
  final int redScore;

  /// 蓝方当前局得分（小比分）
  final int blueScore;

  /// 撤销快照栈：每次加分前记录 [红局, 蓝局, 红分, 蓝分]
  final List<List<int>> history;

  /// 本局已分出胜负（局分已计入，等待开始下一局）
  /// 不保存会导致恢复后首次点击计分区走加分分支而非「开下一局」，错误重复判分
  final bool gameOver;

  /// 存档时间
  final DateTime savedAt;

  /// 数据格式版本号：字段结构变更时递增，便于后续读取旧档时迁移
  /// （与其他游戏存档模型一致；旧存档缺失此字段时视为 1）
  static const int version = 1;

  Map<String, dynamic> toJson() => {
        'version': version,
        'bestOf': bestOf,
        'winScore': winScore,
        'leadBy': leadBy,
        'redGames': redGames,
        'blueGames': blueGames,
        'redScore': redScore,
        'blueScore': blueScore,
        'history': history,
        'gameOver': gameOver,
        'savedAt': savedAt.toIso8601String(),
      };

  factory ScoreboardGameState.fromJson(Map<String, dynamic> json) =>
      ScoreboardGameState(
        bestOf: json['bestOf'] as int,
        winScore: json['winScore'] as int,
        leadBy: json['leadBy'] as int,
        redGames: json['redGames'] as int,
        blueGames: json['blueGames'] as int,
        redScore: json['redScore'] as int,
        blueScore: json['blueScore'] as int,
        history: [
          for (final snapshot in json['history'] as List)
            List<int>.from(snapshot as List),
        ],
        // gameOver 后加入的字段：旧存档缺失时按「局进行中」处理，保持兼容
        gameOver: (json['gameOver'] as bool?) ?? false,
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}
