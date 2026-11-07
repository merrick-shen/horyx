import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/widgets/flash_hint.dart';
import 'package:horyx/shared/widgets/hint_overlay.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.lightOf(AppPalette.brandPrimary),
    home: Scaffold(body: Center(child: child)),
  );

  Finder opacityOf(String text) =>
      find.ancestor(of: find.text(text), matching: find.byType(Opacity));

  testWidgets('文本为空不挂载内容（占位隐藏）', (tester) async {
    await tester.pumpWidget(
      wrap(const HintOverlay(trigger: 0, text: '', accentColor: Colors.red, fontSize: 30)),
    );
    expect(find.byType(FlashHint), findsNothing);
    expect(find.text('提示'), findsNothing);
  });

  testWidgets('文本非空挂载 FlashHint：不拦截触摸，trigger 已带序号立即播放', (tester) async {
    await tester.pumpWidget(
      wrap(const HintOverlay(trigger: 1, text: '提示', accentColor: Colors.red, fontSize: 30)),
    );
    // HintOverlay 自身以 ignoring=true 的 IgnorePointer 包裹（排除框架自带的）
    expect(
      find.ancestor(
        of: find.byType(FlashHint),
        matching: find.byWidgetPredicate(
          (w) => w is IgnorePointer && w.ignoring,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('提示'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<Opacity>(opacityOf('提示')).opacity,
      greaterThan(0.0),
    );
  });
}
