import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:horyx/shared/storage/auto_update_storage.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('未设置时默认开启', () async {
    expect(await AutoUpdateStorage.load(), isTrue);
  });

  test('保存后读取一致', () async {
    await AutoUpdateStorage.save(false);
    expect(await AutoUpdateStorage.load(), isFalse);

    await AutoUpdateStorage.save(true);
    expect(await AutoUpdateStorage.load(), isTrue);
  });
}
