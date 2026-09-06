import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import 'package:horyx/games/word_pk/models/word_entry.dart';

/// 单词校验服务
/// 基于本地词表（约 37 万词）离线校验：无网络请求、毫秒级响应，
/// 满足「检测响应不超过 1 秒」的质量标准
class WordValidator {
  /// 工具类禁止实例化
  WordValidator._();

  /// 词表资源路径
  static const String _assetPath = 'assets/words/english_words.txt';

  /// 词表 Set 缓存（小写存储，单次查询 O(1)）
  static Set<String>? _dictionary;

  /// 预加载词表（AppShell 挂载时预热一次，重复调用无副作用）
  /// 加载失败（资产缺失/损坏等打包异常）时降级为空词表：
  /// 所有单词校验将返回 false（单词PK 无法正常判定），
  /// 但应用可正常启动不白屏——校验不可用远好于整体不可用
  static Future<void> load() async {
    if (_dictionary != null) return;
    try {
      final text = await rootBundle.loadString(_assetPath);
      _dictionary = {
        // 逐行读取并统一小写，trim 兼容换行符差异
        for (final line in text.split('\n')) line.trim().toLowerCase(),
      };
    } catch (e) {
      // 保留失败痕迹（release 下自动静音），便于排查「单词全判无效」类问题
      debugPrint('WordValidator: 词表加载失败，降级为空词表 —— $e');
      _dictionary = const <String>{};
    }
  }

  /// 判断是否为真实存在的英文单词（大小写不敏感）
  /// 需先调用 [load] 完成词表加载，未加载时一律返回 false
  static bool isValid(String word) =>
      word.isNotEmpty && (_dictionary?.contains(word.toLowerCase()) ?? false);

  /// 词法校验（空串 / 纯英文字母），返回拒绝文案；通过返回 null
  /// 单词PK 各提交入口（本地对局、联机客户端、联机房主校验）的
  /// 格式规则唯一来源——改规则（如允许连字符）只需改这里
  static String? validateFormat(String raw) {
    final word = raw.trim();
    if (word.isEmpty) return '请输入英文单词';
    if (!RegExp(r'^[A-Za-z]+$').hasMatch(word)) {
      return '单词只能由英文字母组成';
    }
    return null;
  }

  /// 单词提交完整校验链（格式 → 重复 → 真实性）的唯一来源：
  /// 本地对局与联机房主提交共用，返回统一拒绝文案；通过返回 null。
  /// [raw] 为原始输入（内部统一 trim + 小写后参与比较），
  /// [entries] 为已生效单词表（存储的均为归一化后的单词）
  static String? validateWord(String raw, List<WordEntry> entries) {
    final formatError = validateFormat(raw);
    if (formatError != null) return formatError;
    final word = raw.trim().toLowerCase();
    if (entries.any((e) => e.word == word)) return '单词已重复';
    if (!isValid(word)) return '不是有效的英文单词';
    return null;
  }
}
