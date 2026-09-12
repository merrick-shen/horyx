import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/games/word_pk/services/word_pk_validator.dart';

void main() {
  // 词表为 assets 资源，测试前需初始化绑定并完成加载
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await WordPkValidator.load();
  });

  group('WordPkValidator 单词真实性校验', () {
    test('常见单词为有效单词', () {
      expect(WordPkValidator.isValid('apple'), isTrue);
      expect(WordPkValidator.isValid('banana'), isTrue);
      expect(WordPkValidator.isValid('cherry'), isTrue);
    });

    test('大小写不敏感', () {
      expect(WordPkValidator.isValid('Apple'), isTrue);
      expect(WordPkValidator.isValid('BANANA'), isTrue);
    });

    test('随机字母组合为无效单词', () {
      expect(WordPkValidator.isValid('qqqqzz'), isFalse);
      expect(WordPkValidator.isValid('asdfkx'), isFalse);
    });

    test('空串与空格为无效单词', () {
      expect(WordPkValidator.isValid(''), isFalse);
      expect(WordPkValidator.isValid('  '), isFalse);
    });

    test('非纯字母输入为无效单词', () {
      expect(WordPkValidator.isValid('app1e'), isFalse);
      expect(WordPkValidator.isValid('你好'), isFalse);
    });
  });
}
