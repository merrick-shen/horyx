/// 围棋未完成对局的存档状态
/// 用于「保存并退出」时持久化，下次进入应用可恢复对局
class WeiqiGameState {
  const WeiqiGameState({
    required this.boardSize,
    required this.moves,
    required this.savedAt,
  });

  /// 棋盘路数（9 小盘 / 13 中盘 / 19 标准盘）
  final int boardSize;

  /// 已完成着手序列（落子与虚手按发生顺序记录）
  /// record 含 pass 标记：虚手不落子但参与执子方轮换，悔棋依赖完整序列
  final List<({int col, int row, bool black, bool pass})> moves;

  /// 存档时间
  final DateTime savedAt;

  /// 数据格式版本号：字段结构变更时递增，便于后续读取旧档时迁移
  static const int version = 1;

  Map<String, dynamic> toJson() => {
    'version': version,
    'boardSize': boardSize,
    // record 无法直接序列化，转为 [col, row, black, pass] 四元数组
    'moves': [
      for (final m in moves) [m.col, m.row, m.black, m.pass],
    ],
    'savedAt': savedAt.toIso8601String(),
  };

  /// 反序列化；数据缺失或格式不符时抛出 [FormatException]，由上层容错处理
  factory WeiqiGameState.fromJson(Map<String, dynamic> json) {
    final moveList = json['moves'];
    if (moveList is! List) {
      throw const FormatException('存档 moves 字段无效');
    }
    return WeiqiGameState(
      boardSize: json['boardSize'] as int,
      moves: [
        for (final m in moveList)
          (
            col: (m as List)[0] as int,
            row: m[1] as int,
            black: m[2] as bool,
            pass: m[3] as bool,
          ),
      ],
      savedAt: DateTime.parse(json['savedAt'] as String),
    );
  }
}
