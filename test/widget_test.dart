import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/main.dart';
import 'package:horyx/widgets/game_card.dart';

void main() {
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
}
