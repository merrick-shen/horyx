/// 五子棋未完成对局的存档状态
/// 用于「保存并退出」时持久化，下次进入应用可恢复对局
class GomokuGameState {
  const GomokuGameState({
    required this.boardSize,
    required this.moves,
    required this.savedAt,
  });

  /// 棋盘路数（15 标准盘 / 19 大盘）
  final int boardSize;

  /// 已确认落子序列（索引奇偶决定黑白：0=黑 1=白）
  final List<(int, int)> moves;

  /// 存档时间
  final DateTime savedAt;

  /// 数据格式版本号：字段结构变更时递增，便于后续读取旧档时迁移
  static const int version = 1;

  Map<String, dynamic> toJson() => {
        'version': version,
        'boardSize': boardSize,
        // record 无法直接序列化，转为 [col, row] 二元数组
        'moves': [
          for (final (col, row) in moves) [col, row],
        ],
        'savedAt': savedAt.toIso8601String(),
      };

  /// 反序列化；数据缺失或格式不符时抛出 [FormatException]，由上层容错处理
  factory GomokuGameState.fromJson(Map<String, dynamic> json) {
    final moveList = json['moves'];
    if (moveList is! List) {
      throw const FormatException('存档 moves 字段无效');
    }
    return GomokuGameState(
      boardSize: json['boardSize'] as int,
      moves: [
        for (final m in moveList)
          (
            (m as List)[0] as int,
            m[1] as int,
          ),
      ],
      savedAt: DateTime.parse(json['savedAt'] as String),
    );
  }
}
