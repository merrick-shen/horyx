import 'word_entry.dart';

/// 单词PK未完成对局的存档状态
/// 用于「保存并退出」时持久化，下次进入应用可恢复对战
class WordPkGameState {
  const WordPkGameState({
    required this.playerCount,
    required this.currentPlayer,
    required this.entries,
    required this.savedAt,
  });

  /// 参与人数
  final int playerCount;

  /// 当前输入者序号（从 1 开始）
  final int currentPlayer;

  /// 已验证通过的单词列表
  final List<WordEntry> entries;

  /// 存档时间
  final DateTime savedAt;

  /// 数据格式版本号：字段结构变更时递增，便于后续读取旧档时迁移
  static const int version = 1;

  Map<String, dynamic> toJson() => {
        'version': version,
        'playerCount': playerCount,
        'currentPlayer': currentPlayer,
        'entries': [
          for (final e in entries)
            {'word': e.word, 'playerIndex': e.playerIndex},
        ],
        'savedAt': savedAt.toIso8601String(),
      };

  /// 反序列化；数据缺失或格式不符时抛出 [FormatException]，由上层容错处理
  factory WordPkGameState.fromJson(Map<String, dynamic> json) {
    final entryList = json['entries'];
    if (entryList is! List) {
      throw const FormatException('存档 entries 字段无效');
    }
    return WordPkGameState(
      playerCount: json['playerCount'] as int,
      currentPlayer: json['currentPlayer'] as int,
      entries: [
        for (final e in entryList)
          WordEntry(
            word: (e as Map<String, dynamic>)['word'] as String,
            playerIndex: e['playerIndex'] as int,
          ),
      ],
      savedAt: DateTime.parse(json['savedAt'] as String),
    );
  }
}
