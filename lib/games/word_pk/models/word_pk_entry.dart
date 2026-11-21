/// 已验证通过的 PK 单词条目
class WordPkEntry {
  const WordPkEntry({required this.word, required this.playerIndex});

  /// 单词文本（统一小写存储，便于重复检测时忽略大小写）
  final String word;

  /// 输入该单词的玩家序号（从 1 开始）
  final int playerIndex;

  /// 值相等：退出保存判定「恢复后无变化」经 listEquals 逐项比较依赖此语义，
  /// 不再依赖引用恰好一致
  @override
  bool operator ==(Object other) =>
      other is WordPkEntry &&
      other.word == word &&
      other.playerIndex == playerIndex;

  @override
  int get hashCode => Object.hash(word, playerIndex);
}
