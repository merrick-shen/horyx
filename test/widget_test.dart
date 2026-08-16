import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/game_navigation.dart';
import 'helpers/test_app.dart';

/// 主页与导航测试
/// 各游戏功能测试见 word_pk_test / gomoku_test / weiqi_test / scoreboard_test，
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

  testWidgets('点击第三张卡片进入围棋设置页', (tester) async {
    await pumpApp(tester);

    // 点击游戏列表第三张卡片（围棋）
    await openGame(tester, 2);

    // 设置页：顶栏游戏名 + 三档规格 + 开始按钮
    expect(find.text('围棋'), findsOneWidget);
    expect(find.text('9×9'), findsOneWidget);
    expect(find.text('13×13'), findsOneWidget);
    expect(find.text('19×19'), findsOneWidget);
    expect(find.text('开始对局'), findsOneWidget);

    // 顶栏返回回主页（设置阶段直接返回，无确认弹窗）
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Horyx'), findsOneWidget);
  });

  testWidgets('左滑切换到更多页，右滑切回首页', (tester) async {
    await pumpApp(tester);

    // 左滑（手势向左）切换到更多页，底部导航联动选中「更多」
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('存档管理'), findsOneWidget);
    expect(find.text('Horyx'), findsNothing);

    // 右滑切回首页
    await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Horyx'), findsOneWidget);
  });

  testWidgets('滑动距离不足时回弹到原页面，导航点击平滑切换', (tester) async {
    await pumpApp(tester);

    // 小距离拖动后松手：未过切换阈值，页面回弹停留在首页
    final gesture = await tester.startGesture(const Offset(300, 400));
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Horyx'), findsOneWidget);
    expect(find.text('存档管理'), findsNothing);

    // 点击底部导航「更多」：经动画平滑切换
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    expect(find.text('存档管理'), findsOneWidget);
  });
}
