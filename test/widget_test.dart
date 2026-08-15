import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:horyx/main.dart';
import 'package:horyx/services/word_validator.dart';
import 'package:horyx/widgets/game_card.dart';

void main() {
  // 测试直接 pumpWidget 不经过 main()，需手动预加载单词词表
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await WordValidator.load();
  });

  // 每个测试使用独立的模拟本地存储
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('主页静态 UI 冒烟测试', (tester) async {
    await tester.pumpWidget(const MyApp());

    // 顶栏展示品牌名
    expect(find.text('Horyx'), findsOneWidget);
    // 游戏列表已渲染出占位卡片
    expect(find.text('开发中'), findsWidgets);
    // 底部导航栏包含首页与设置入口
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('点击第一张卡片进入单词PK游戏页', (tester) async {
    await tester.pumpWidget(const MyApp());

    // 点击游戏列表第一张卡片
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();

    // 进入游戏页：顶栏展示「单词PK」且无底部导航栏
    expect(find.text('单词PK'), findsOneWidget);
    expect(find.text('设置'), findsNothing);
  });

  testWidgets('单词PK：人数设置与对局视图切换', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();

    // 设置视图：人数选择与开始按钮
    expect(find.text('参与人数'), findsOneWidget);
    expect(find.text('开始 PK'), findsOneWidget);

    // 选择 3 人并开始
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始 PK'));
    await tester.pumpAndSettle();

    // 对局视图：当前输入者、玩家序列、输入框
    expect(find.text('当前输入者'), findsOneWidget);
    expect(find.text('玩家 3'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    // 初始无单词，显示空状态（多行文案用包含匹配）
    expect(find.textContaining('还没有验证通过的单词'), findsOneWidget);
  });

  testWidgets('单词PK：提交流程（入列、轮换、重复与无效提示）', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始 PK'));
    await tester.pumpAndSettle();

    // 玩家1 输入有效单词：入列并轮换到玩家2
    await tester.enterText(find.byType(TextField), 'apple');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(find.text('apple'), findsOneWidget);
    expect(find.text('1 个'), findsOneWidget);

    // 玩家2 输入重复单词（忽略大小写）：提示且不入列、不轮换
    await tester.enterText(find.byType(TextField), 'Apple');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(find.text('单词已重复'), findsOneWidget);
    expect(find.text('1 个'), findsOneWidget);

    // 关闭提示后输入无效单词：提示不通过
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'qqqqzz');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(find.text('不是有效的英文单词'), findsOneWidget);
    expect(find.text('1 个'), findsOneWidget);

    // 关闭提示后输入非字母：提示不通过
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'app1e');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(find.text('单词只能由英文字母组成'), findsOneWidget);
  });

  testWidgets('单词PK：退出弹窗与保存恢复流程', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始 PK'));
    await tester.pumpAndSettle();

    // 玩家1 输入单词后轮换至玩家2
    await tester.enterText(find.byType(TextField), 'apple');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    // 对局中点击顶栏返回：弹出确认弹窗（三选项）
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.text('退出对局？'), findsOneWidget);
    expect(find.text('保存并退出'), findsOneWidget);
    expect(find.text('不保存并退出'), findsOneWidget);

    // 取消：留在对局
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('当前输入者'), findsOneWidget);

    // 再次返回并确认保存：退出游戏页回到主页
    // （主页第一张卡片名称也是「单词PK」，故以对局元素消失判断退出成功）
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存并退出'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('当前输入者'), findsNothing);
    expect(find.text('Horyx'), findsOneWidget);

    // 重新进入游戏页：展示「继续上次对局」入口
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();
    expect(find.text('继续上次对局'), findsOneWidget);

    // 点击继续：恢复对局进度（单词与当前输入者玩家2）
    await tester.tap(find.text('继续上次对局'));
    await tester.pumpAndSettle();
    expect(find.text('apple'), findsOneWidget);
    expect(find.text('当前输入者'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_rounded), findsOneWidget);
  });

  testWidgets('单词PK：不保存并退出丢弃对局', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始 PK'));
    await tester.pumpAndSettle();

    // 输入一个单词后选择「不保存并退出」
    await tester.enterText(find.byType(TextField), 'apple');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不保存并退出'));
    await tester.pumpAndSettle();
    expect(find.text('Horyx'), findsOneWidget);

    // 重新进入：存档已清除，不再展示继续入口
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();
    expect(find.text('继续上次对局'), findsNothing);
    expect(find.text('参与人数'), findsOneWidget);
  });

  testWidgets('单词PK：错误提示未关闭时退出不残留到主页', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始 PK'));
    await tester.pumpAndSettle();

    // 触发错误提示（重复单词）且不关闭
    await tester.enterText(find.byType(TextField), 'apple');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'apple');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(find.text('单词已重复'), findsOneWidget);

    // 提示未关闭时保存并退出：提示不应残留到主页
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存并退出'));
    await tester.pumpAndSettle();
    expect(find.text('Horyx'), findsOneWidget);
    expect(find.text('单词已重复'), findsNothing);
    expect(find.text('知道了'), findsNothing);
  });

  testWidgets('设置页：主题入口跳转主题设置页', (tester) async {
    await tester.pumpWidget(const MyApp());

    // 切换到底部导航「设置」页
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    // 设置页展示主题设置入口
    expect(find.text('主题'), findsOneWidget);

    // 点击进入主题设置页（当前为占位）
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();
    expect(find.text('主题设置'), findsOneWidget);
    expect(find.textContaining('功能开发中'), findsOneWidget);
  });
}
