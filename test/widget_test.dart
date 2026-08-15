import 'package:flutter/material.dart';
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

    // 对局视图：当前输入者、玩家序列（含玩家3）、输入框
    expect(find.text('当前输入者'), findsOneWidget);
    // 「玩家 3」同时出现在玩家序列与演示单词标签中
    expect(find.text('玩家 3'), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
    // 单词列表为静态演示数据
    expect(find.text('apple'), findsOneWidget);
  });
}
