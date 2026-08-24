import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/games/word_pk/services/word_validator.dart';

void main() {
  // 词表为 assets 资源，测试前需初始化绑定并完成加载
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await WordValidator.load();
  });

  group('WordValidator 单词真实性校验', () {
    test('常见单词为有效单词', () {
      expect(WordValidator.isValid('apple'), isTrue);
      expect(WordValidator.isValid('banana'), isTrue);
      expect(WordValidator.isValid('cherry'), isTrue);
    });

    test('大小写不敏感', () {
      expect(WordValidator.isValid('Apple'), isTrue);
      expect(WordValidator.isValid('BANANA'), isTrue);
    });

    test('随机字母组合为无效单词', () {
      expect(WordValidator.isValid('qqqqzz'), isFalse);
      expect(WordValidator.isValid('asdfkx'), isFalse);
    });

    test('空串与空格为无效单词', () {
      expect(WordValidator.isValid(''), isFalse);
      expect(WordValidator.isValid('  '), isFalse);
    });

    test('非纯字母输入为无效单词', () {
      expect(WordValidator.isValid('app1e'), isFalse);
      expect(WordValidator.isValid('你好'), isFalse);
    });
  });
}
