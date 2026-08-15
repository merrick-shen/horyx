import 'package:flutter/services.dart' show rootBundle;

/// 单词真实性校验服务
/// 基于本地词表（google-10000 常用英文词表，约 1 万词）离线校验：
/// 无网络请求、毫秒级响应，满足「检测响应不超过 1 秒」的质量标准
class WordValidator {
  /// 工具类禁止实例化
  WordValidator._();

  /// 词表资源路径
  static const String _assetPath = 'assets/words/english_10k.txt';

  /// 词表 Set 缓存（小写存储，单次查询 O(1)）
  static Set<String>? _dictionary;

  /// 预加载词表（应用启动时调用一次，重复调用无副作用）
  static Future<void> load() async {
    if (_dictionary != null) return;
    final text = await rootBundle.loadString(_assetPath);
    _dictionary = {
      // 逐行读取并统一小写，trim 兼容换行符差异
      for (final line in text.split('\n')) line.trim().toLowerCase(),
    };
  }

  /// 判断是否为真实存在的英文单词（大小写不敏感）
  /// 需先调用 [load] 完成词表加载，未加载时一律返回 false
  static bool isValid(String word) =>
      word.isNotEmpty && (_dictionary?.contains(word.toLowerCase()) ?? false);
}
