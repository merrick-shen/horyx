import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horyx/app/pages/settings/archive_page.dart';
import 'package:horyx/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.lightOf(AppPalette.brandPrimary),
        home: child,
      );

  testWidgets('无任何存档时显示空状态提示而非空白', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(wrap(const ArchivePage()));
    await tester.pumpAndSettle();

    expect(find.text('暂无存档'), findsOneWidget);
  });

  testWidgets('索引键存在但为空列表时同样显示空状态提示', (tester) async {
    SharedPreferences.setMockInitialValues({'archive_index_v2': '[]'});
    await tester.pumpWidget(wrap(const ArchivePage()));
    await tester.pumpAndSettle();

    expect(find.text('暂无存档'), findsOneWidget);
  });
}
