import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/widgets/flash_hint.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.lightOf(AppPalette.brandPrimary),
    home: Scaffold(body: Center(child: child)),
  );

  Finder opacityOf(String text) =>
      find.ancestor(of: find.text(text), matching: find.byType(Opacity));

  testWidgets('初始不显示（trigger 为 0 无动画）', (tester) async {
    await tester.pumpWidget(
      wrap(
        const FlashHint(
          trigger: 0,
          text: '提示',
          accentColor: Colors.red,
          fontSize: 30,
        ),
      ),
    );
    // 文本在树中但透明度为 0（动画未启动）
    expect(find.text('提示'), findsOneWidget);
    expect(tester.widget<Opacity>(opacityOf('提示')).opacity, 0.0);
  });

  testWidgets('trigger 递增播放一遍动画：播完归零，再次递增重播', (tester) async {
    await tester.pumpWidget(
      wrap(
        const FlashHint(
          trigger: 1,
          text: '提示',
          accentColor: Colors.red,
          fontSize: 30,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(opacityOf('提示')).opacity, 0.0);

    await tester.pumpWidget(
      wrap(
        const FlashHint(
          trigger: 2,
          text: '提示',
          accentColor: Colors.red,
          fontSize: 30,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<Opacity>(opacityOf('提示')).opacity, greaterThan(0.0));
  });
}
