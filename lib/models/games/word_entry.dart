/// 已验证通过的 PK 单词条目
class WordEntry {
  const WordEntry({required this.word, required this.playerIndex});

  /// 单词文本（统一小写存储，便于重复检测时忽略大小写）
  final String word;

  /// 输入该单词的玩家序号（从 1 开始）
  final int playerIndex;
}
