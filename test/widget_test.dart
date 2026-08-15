import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/game_navigation.dart';
import 'helpers/test_app.dart';

/// 主页与导航测试
/// 各游戏功能测试见 word_pk_test / gomoku_test / scoreboard_test，
/// 设置与主题测试见 settings_test
void main() {
  setUpTestEnv();

  testWidgets('主页静态 UI 冒烟测试', (tester) async {
    await pumpApp(tester);

    // 顶栏展示品牌名
    expect(find.text('Horyx'), findsOneWidget);
    // 游戏列表已上线的四款游戏
    expect(find.text('单词PK'), findsOneWidget);
    expect(find.text('五子棋'), findsOneWidget);
    expect(find.text('围棋'), findsOneWidget);
    expect(find.text('计分器'), findsOneWidget);
    // 开发中占位卡片已移除
    expect(find.text('开发中'), findsNothing);
    // 底部导航栏包含首页与更多入口
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);
  });

  testWidgets('点击第一张卡片进入单词PK游戏页', (tester) async {
    await pumpApp(tester);
    await openWordPk(tester);

    // 进入游戏页：顶栏展示「单词PK」且无底部导航栏
    expect(find.text('单词PK'), findsOneWidget);
    expect(find.text('更多'), findsNothing);
  });

  testWidgets('点击第三张卡片进入围棋占位页', (tester) async {
    await pumpApp(tester);

    // 点击游戏列表第三张卡片（围棋，玩法待开发）
    await openGame(tester, 2);

    // 占位页：顶栏展示游戏名 + 开发中提示
    expect(find.byIcon(Icons.blur_on_rounded), findsWidgets);
    expect(find.text('功能开发中，敬请期待'), findsOneWidget);

    // 顶栏返回回主页
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Horyx'), findsOneWidget);
  });
}
