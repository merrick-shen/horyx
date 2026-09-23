import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/widgets/option_block.dart';

void main() {
  // NumberOptionBlock 步进按钮的核心语义：基准值选取、validate 感知跳步
  // （计分器赛制「仅允许奇数」）、边界与非法态禁用
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode();
  });

  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  Widget wrap(NumberOptionBlock child) => MaterialApp(
        theme: AppTheme.lightOf(AppPalette.brandPrimary),
        home: Scaffold(body: child),
      );

  testWidgets('点 + 生效 +1 并上报 onValid', (tester) async {
    var valid = 0;
    controller.text = '3';
    await tester.pumpWidget(wrap(NumberOptionBlock(
      controller: controller,
      focusNode: focusNode,
      hintText: '',
      min: 1,
      max: 99,
      onValid: (v) => valid = v,
      onCleared: () {},
    )));
    await tester.tap(find.byIcon(Icons.add_rounded));
    expect(valid, 4);
    expect(controller.text, '4');
  });

  testWidgets('validate 拒绝的值被跳过：奇数块步进落在相邻奇数', (tester) async {
    var valid = 0;
    controller.text = '3';
    await tester.pumpWidget(wrap(NumberOptionBlock(
      controller: controller,
      focusNode: focusNode,
      hintText: '',
      min: 1,
      max: 31,
      validate: (v) => v.isOdd,
      onValid: (v) => valid = v,
      onCleared: () {},
    )));
    await tester.tap(find.byIcon(Icons.add_rounded));
    expect(valid, 5);
    await tester.tap(find.byIcon(Icons.remove_rounded));
    expect(valid, 3);
  });

  testWidgets('到达边界对应按钮禁用（tap 无效）', (tester) async {
    var valid = 0;
    controller.text = '1';
    await tester.pumpWidget(wrap(NumberOptionBlock(
      controller: controller,
      focusNode: focusNode,
      hintText: '',
      min: 1,
      max: 99,
      onValid: (v) => valid = v,
      onCleared: () {},
    )));
    await tester.tap(find.byIcon(Icons.remove_rounded));
    expect(valid, 0);
    expect(controller.text, '1');
  });

  testWidgets('空输入以 defaultValue 为基准步进', (tester) async {
    var valid = 0;
    await tester.pumpWidget(wrap(NumberOptionBlock(
      controller: controller,
      focusNode: focusNode,
      hintText: '',
      min: 1,
      max: 31,
      validate: (v) => v.isOdd,
      defaultValue: 3,
      onValid: (v) => valid = v,
      onCleared: () {},
    )));
    await tester.tap(find.byIcon(Icons.add_rounded));
    expect(valid, 5);
    expect(controller.text, '5');
  });

  testWidgets('红边非法态步进禁用（tap 无效且不触发 onCleared）', (tester) async {
    var valid = 0;
    var cleared = false;
    controller.text = '999';
    await tester.pumpWidget(wrap(NumberOptionBlock(
      controller: controller,
      focusNode: focusNode,
      hintText: '',
      min: 1,
      max: 99,
      onValid: (v) => valid = v,
      onCleared: () => cleared = true,
    )));
    await tester.tap(find.byIcon(Icons.add_rounded));
    expect(valid, 0);
    expect(cleared, isFalse);
    expect(controller.text, '999');
  });
}
