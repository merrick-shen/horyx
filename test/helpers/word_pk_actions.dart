import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'game_navigation.dart';

/// 进入单词PK并开始对局（默认 2 人）
/// 需要其他人数时使用 [openWordPk] 自行选择后再开始
Future<void> startWordPk(WidgetTester tester) async {
  await openWordPk(tester);
  await tester.tap(find.text('开始 PK'));
  await tester.pumpAndSettle();
}

/// 输入单词并提交
Future<void> submitWord(WidgetTester tester, String word) async {
  await tester.enterText(find.byType(TextField), word);
  await tester.tap(find.text('提交'));
  await tester.pumpAndSettle();
}

/// 对局中点击顶栏返回（触发退出确认弹窗）
Future<void> tapWordPkBack(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
  await tester.pumpAndSettle();
}
