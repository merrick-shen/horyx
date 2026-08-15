import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:horyx/main.dart';
import 'package:horyx/services/word_validator.dart';

/// 测试环境统一前置：词表预加载 + 独立模拟存储
/// 必须在各测试文件 main() 的顶层同步调用（setUpAll/setUp 需在 main 内注册）
void setUpTestEnv() {
  // 测试直接 pumpWidget 不经过 main()，需手动预加载单词词表
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await WordValidator.load();
  });

  // 每个测试使用独立的模拟本地存储
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
}

/// 启动应用并等待首帧（所有用例的统一入口）
Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const MyApp());
}
