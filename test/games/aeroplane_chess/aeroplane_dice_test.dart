import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/games/aeroplane_chess/widgets/aeroplane_dice.dart';
import 'package:horyx/shared/theme/app_theme.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.lightOf(AppPalette.brandPrimary),
        home: Scaffold(body: Center(child: child)),
      );

  int pipCount(WidgetTester tester) => find
      .byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle,
      )
      .evaluate()
      .length;

  for (final value in [1, 2, 3, 4, 5, 6]) {
    testWidgets('点数 $value 渲染对应数量的骰面点', (tester) async {
      await tester.pumpWidget(wrap(AeroplaneDice(value: value)));
      expect(pipCount(tester), value);
    });
  }

  testWidgets('尺寸按参数渲染为正方形', (tester) async {
    await tester.pumpWidget(wrap(const AeroplaneDice(value: 3, size: 40)));
    expect(tester.getSize(find.byType(AeroplaneDice)), const Size(40, 40));
  });

  test('非法点数构造时抛错', () {
    expect(() => AeroplaneDice(value: 0), throwsA(isA<AssertionError>()));
    expect(() => AeroplaneDice(value: 7), throwsA(isA<AssertionError>()));
  });
}
