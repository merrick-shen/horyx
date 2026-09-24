import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:horyx/shared/storage/profile_storage.dart';

void main() {
  setUp(() {
    // 每个测试使用独立的模拟存储，避免相互污染
    SharedPreferences.setMockInitialValues({});
  });

  group('ProfileStorage 名字存储', () {
    test('未写入时 load 返回 null', () async {
      expect(await ProfileStorage.load(), isNull);
    });

    test('save 后 load 返回一致', () async {
      await ProfileStorage.save('小明');
      expect(await ProfileStorage.load(), '小明');
    });

    test('空串归一化为 null（未设置）', () async {
      final prefs = await SharedPreferences.getInstance();
      // 模拟历史脏数据：存储中存在空串
      await prefs.setString('user_name', '');
      expect(await ProfileStorage.load(), isNull);
    });
  });
}
