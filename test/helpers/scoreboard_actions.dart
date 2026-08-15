import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'game_navigation.dart';

/// 滚动到可见并点击「开始计分」
/// 设置内容可能超出默认测试视口，直接 tap 会因不可见而失效
Future<void> tapStartScoring(WidgetTester tester) async {
  await tester.ensureVisible(find.text('开始计分'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('开始计分'));
  await tester.pumpAndSettle();
}

/// 进入计分器并开始计分
/// 三个配置参数为 null 时跳过输入（沿用当前值或默认值）
Future<void> startScoreboard(
  WidgetTester tester, {
  String? bestOf,
  String? winScore,
  String? lead,
}) async {
  await openScoreboard(tester);
  if (bestOf != null) {
    await tester.enterText(find.byKey(const Key('bestOfInput')), bestOf);
    await tester.pumpAndSettle();
  }
  if (winScore != null) {
    await tester.enterText(find.byKey(const Key('winScoreInput')), winScore);
    await tester.pumpAndSettle();
  }
  if (lead != null) {
    await tester.enterText(find.byKey(const Key('leadInput')), lead);
    await tester.pumpAndSettle();
  }
  await tapStartScoring(tester);
}

/// 点击计分区为指定方加 1 分，[times] 可连点多次（每次等待界面稳定）
Future<void> tapPanel(WidgetTester tester, bool red, [int times = 1]) async {
  final panel = find.byKey(Key(red ? 'redPanel' : 'bluePanel'));
  for (var i = 0; i < times; i++) {
    await tester.tap(panel);
    await tester.pumpAndSettle();
  }
}
