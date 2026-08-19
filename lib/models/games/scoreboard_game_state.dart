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

  /// 存档时间
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'bestOf': bestOf,
        'winScore': winScore,
        'leadBy': leadBy,
        'redGames': redGames,
        'blueGames': blueGames,
        'redScore': redScore,
        'blueScore': blueScore,
        'history': history,
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
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}
