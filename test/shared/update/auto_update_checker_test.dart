import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:horyx/shared/storage/ignored_version_storage.dart';
import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/update/auto_update_checker.dart';
import 'package:horyx/shared/update/models/release_info.dart';
import 'package:horyx/shared/update/update_service.dart';

/// AutoUpdateChecker 分发行为测试
/// stub 服务覆写 check 返回固定三态；flutter test 恒为 Debug 构建，
/// 通过覆写 debugSkip 开关分别验证「默认短路」与「三态分发」两条路径
void main() {
  const release = ReleaseInfo(
    tagName: 'v9.9.9',
    name: '新版本',
    body: '更新说明',
    htmlUrl: 'https://example.com/release',
    downloadUrl: 'https://example.com/app.apk',
  );

  late _StubUpdateService service;

  setUp(() {
    // 忽略版本记录走 SharedPreferences：注入空 mock 隔离真实平台通道
    SharedPreferences.setMockInitialValues({});
    service = _StubUpdateService(result: const UpdateUpToDate());
  });

  tearDown(() {
    // 恢复默认短路状态，避免用例间串扰
    AutoUpdateChecker.debugSkip = kDebugMode;
  });

  /// 挂载带主题（弹窗依赖 context.palette）的页面并推进
  /// checker 的完整时间线：首帧 → 3 秒延迟 → 检查分发与弹窗动画
  Future<void> runChecker(WidgetTester tester) async {
    late BuildContext testContext;
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
    unawaited(
      AutoUpdateChecker(updateService: service).checkIfNeeded(testContext),
    );
    await tester.pump(); // 首帧完成（endOfFrame）
    await tester.pump(const Duration(seconds: 3)); // 3 秒延迟
    await tester.pumpAndSettle(); // 检查结果分发与弹窗动画落定
  }

  group('AutoUpdateChecker.checkIfNeeded', () {
    testWidgets('Debug 构建默认短路：不发起检查、无任何 UI', (tester) async {
      // flutter test 环境下 debugSkip 默认为 true，不覆写
      await runChecker(tester);

      expect(service.callCount, 0);
      expect(find.textContaining('发现新版本'), findsNothing);
    });

    group('三态分发（debugSkip 覆写为 false）', () {
      setUp(() => AutoUpdateChecker.debugSkip = false);

      testWidgets('有新版本 → 弹出「发现新版本」弹窗（含忽略此版本）', (
        tester,
      ) async {
        service.result = UpdateAvailable(release);
        await runChecker(tester);

        expect(service.callCount, 1);
        expect(find.text('发现新版本 v9.9.9'), findsOneWidget);
        expect(find.text('前往下载'), findsOneWidget);
        expect(find.text('忽略此版本'), findsOneWidget);
      });

      testWidgets('版本已被忽略 → 静默返回，无弹窗', (tester) async {
        await IgnoredVersionStorage.save(release.tagName);
        service.result = UpdateAvailable(release);
        await runChecker(tester);

        expect(service.callCount, 1);
        expect(find.textContaining('发现新版本'), findsNothing);
      });

      testWidgets('点击「忽略此版本」→ 记录忽略版本，关闭弹窗', (tester) async {
        service.result = UpdateAvailable(release);
        await runChecker(tester);

        await tester.tap(find.text('忽略此版本'));
        await tester.pumpAndSettle();

        expect(find.textContaining('发现新版本'), findsNothing);
        expect(await IgnoredVersionStorage.isIgnored(release.tagName), isTrue);
      });

      testWidgets('已是最新 → 静默返回，无弹窗', (tester) async {
        service.result = const UpdateUpToDate();
        await runChecker(tester);

        expect(service.callCount, 1);
        expect(find.textContaining('发现新版本'), findsNothing);
      });

      testWidgets('检查失败 → 静默返回，无弹窗', (tester) async {
        service.result = const UpdateCheckFailed();
        await runChecker(tester);

        expect(service.callCount, 1);
        expect(find.textContaining('发现新版本'), findsNothing);
      });

      testWidgets('检查抛异常 → 兜底吞掉，无弹窗无崩溃', (tester) async {
        service.throwInCheck = Exception('网络异常');
        await runChecker(tester);

        expect(service.callCount, 1);
        expect(find.textContaining('发现新版本'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });
  });
}

/// 固定返回三态之一的 stub 服务（super 构造不发起任何真实请求）
class _StubUpdateService extends UpdateService {
  _StubUpdateService({this.result});

  /// check 返回值；throwInCheck 非空时改为抛错
  UpdateCheckResult? result;
  Object? throwInCheck;
  int callCount = 0;

  @override
  Future<UpdateCheckResult> check() async {
    callCount++;
    if (throwInCheck != null) throw throwInCheck!;
    return result!;
  }
}
