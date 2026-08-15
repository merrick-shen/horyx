import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/game_navigation.dart';
import 'helpers/test_app.dart';
import 'helpers/word_pk_actions.dart';

/// 单词PK 功能测试
void main() {
  setUpTestEnv();

  testWidgets('单词PK：人数设置与对局视图切换', (tester) async {
    await pumpApp(tester);
    await openWordPk(tester);

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
    await pumpApp(tester);
    await startWordPk(tester);

    // 玩家1 输入有效单词：入列并轮换到玩家2
    await submitWord(tester, 'apple');
    expect(find.text('apple'), findsOneWidget);
    expect(find.text('1 个'), findsOneWidget);

    // 玩家2 输入重复单词（忽略大小写）：提示且不入列、不轮换
    await submitWord(tester, 'Apple');
    expect(find.text('单词已重复'), findsOneWidget);
    expect(find.text('1 个'), findsOneWidget);

    // 关闭提示后输入无效单词：提示不通过
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await submitWord(tester, 'qqqqzz');
    expect(find.text('不是有效的英文单词'), findsOneWidget);
    expect(find.text('1 个'), findsOneWidget);

    // 关闭提示后输入非字母：提示不通过
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await submitWord(tester, 'app1e');
    expect(find.text('单词只能由英文字母组成'), findsOneWidget);
  });

  testWidgets('单词PK：退出弹窗与保存恢复流程', (tester) async {
    await pumpApp(tester);
    await startWordPk(tester);

    // 玩家1 输入单词后轮换至玩家2
    await submitWord(tester, 'apple');

    // 对局中点击顶栏返回：弹出确认弹窗（三选项）
    await tapWordPkBack(tester);
    expect(find.text('退出对局？'), findsOneWidget);
    expect(find.text('保存并退出'), findsOneWidget);
    expect(find.text('不保存并退出'), findsOneWidget);

    // 取消：留在对局
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('当前输入者'), findsOneWidget);

    // 再次返回并确认保存：退出游戏页回到主页
    // （主页第一张卡片名称也是「单词PK」，故以对局元素消失判断退出成功）
    await tapWordPkBack(tester);
    await tester.tap(find.text('保存并退出'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('当前输入者'), findsNothing);
    expect(find.text('Horyx'), findsOneWidget);

    // 重新进入游戏页：展示「继续上次对局」入口
    await openWordPk(tester);
    expect(find.text('继续上次对局'), findsOneWidget);

    // 点击继续：恢复对局进度（单词与当前输入者玩家2）
    await tester.tap(find.text('继续上次对局'));
    await tester.pumpAndSettle();
    expect(find.text('apple'), findsOneWidget);
    expect(find.text('当前输入者'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_rounded), findsOneWidget);
  });

  testWidgets('单词PK：不保存并退出丢弃对局', (tester) async {
    await pumpApp(tester);
    await startWordPk(tester);

    // 输入一个单词后选择「不保存并退出」
    await submitWord(tester, 'apple');
    await tapWordPkBack(tester);
    await tester.tap(find.text('不保存并退出'));
    await tester.pumpAndSettle();
    expect(find.text('Horyx'), findsOneWidget);

    // 重新进入：存档已清除，不再展示继续入口
    await openWordPk(tester);
    expect(find.text('继续上次对局'), findsNothing);
    expect(find.text('参与人数'), findsOneWidget);
  });

  testWidgets('单词PK：错误提示未关闭时退出不残留到主页', (tester) async {
    await pumpApp(tester);
    await startWordPk(tester);

    // 触发错误提示（重复单词）且不关闭
    await submitWord(tester, 'apple');
    await submitWord(tester, 'apple');
    expect(find.text('单词已重复'), findsOneWidget);

    // 提示未关闭时保存并退出：提示不应残留到主页
    await tapWordPkBack(tester);
    await tester.tap(find.text('保存并退出'));
    await tester.pumpAndSettle();
    expect(find.text('Horyx'), findsOneWidget);
    expect(find.text('单词已重复'), findsNothing);
    expect(find.text('知道了'), findsNothing);
  });
}
