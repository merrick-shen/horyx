import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/update/models/release_info.dart';
import 'package:horyx/shared/widgets/update_available_dialog.dart';

/// 更新弹窗按钮形态与返回值测试
/// 手动检查形态（默认）不展示「忽略此版本」；自动检查形态展示，
/// 各按钮与关闭弹窗分别返回对应选择
void main() {
  const release = ReleaseInfo(
    tagName: 'v9.9.9',
    name: '新版本',
    body: '更新说明',
    htmlUrl: 'https://example.com/release',
    downloadUrl: 'https://example.com/app.apk',
  );

  late BuildContext testContext;

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkOf(AppPalette.brandPrimary),
        home: Builder(
          builder: (context) {
            testContext = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );
  }

  /// 打开弹窗并返回选择 future（同步返回，不等待关闭；
  /// 用例内先 pumpAndSettle 让弹窗出现，操作后再 await 该 future）
  Future<UpdateDialogChoice> openDialog({bool showIgnoreVersion = false}) {
    return showUpdateAvailableDialog(
      testContext,
      release: release,
      showIgnoreVersion: showIgnoreVersion,
    );
  }

  testWidgets('手动检查形态：无「忽略此版本」，点「前往下载」返回 download', (
    tester,
  ) async {
    await pumpHost(tester);
    final result = openDialog();
    await tester.pumpAndSettle();

    expect(find.text('下次再说'), findsOneWidget);
    expect(find.text('前往下载'), findsOneWidget);
    expect(find.text('忽略此版本'), findsNothing);

    await tester.tap(find.text('前往下载'));
    await tester.pumpAndSettle();
    expect(await result, UpdateDialogChoice.download);
  });

  testWidgets('自动检查形态：展示「忽略此版本」，点击返回 ignore', (
    tester,
  ) async {
    await pumpHost(tester);
    final result = openDialog(showIgnoreVersion: true);
    await tester.pumpAndSettle();

    expect(find.text('忽略此版本'), findsOneWidget);

    await tester.tap(find.text('忽略此版本'));
    await tester.pumpAndSettle();
    expect(await result, UpdateDialogChoice.ignore);
  });

  testWidgets('点击遮罩关闭弹窗视为「下次再说」', (tester) async {
    await pumpHost(tester);
    final result = openDialog(showIgnoreVersion: true);
    await tester.pumpAndSettle();

    // 点击弹窗外区域触发遮罩关闭
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(await result, UpdateDialogChoice.later);
  });
}
