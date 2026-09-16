import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:horyx/shared/update/github_release_api.dart';
import 'package:horyx/shared/update/models/release_info.dart';
import 'package:horyx/shared/update/update_service.dart';

/// UpdateService 三态判定测试
/// fake API 直接覆写 fetchLatest，脱离真实 HTTP；版本加载器注入固定版本
void main() {
  PackageInfo packageInfo(String version) => PackageInfo(
    appName: 'Horyx',
    packageName: 'horyx',
    version: version,
    buildNumber: '9',
  );

  ReleaseInfo releaseOf(String tagName) => ReleaseInfo(
    tagName: tagName,
    name: tagName,
    body: '说明',
    htmlUrl: 'https://example.com/release',
    downloadUrl: 'https://example.com/app.apk',
  );

  /// fetchLatest 返回固定 Release 的 fake
  FakeApi apiOf(String tagName) => FakeApi(releaseOf(tagName));

  UpdateService serviceOf({
    required GitHubReleaseApi api,
    required String version,
  }) => UpdateService(
    api: api,
    packageInfoLoader: () async => packageInfo(version),
  );

  group('check 三态判定', () {
    test('release 版本新于本地 → available 且携带 Release 详情', () async {
      final api = apiOf('v1.0.0');
      final result = await serviceOf(api: api, version: '0.9.0').check();

      expect(result, isA<UpdateAvailable>());
      final available = result as UpdateAvailable;
      expect(available.release.tagName, 'v1.0.0');
      expect(available.release.downloadUrl, 'https://example.com/app.apk');
    });

    test('release 与本地同版本 → upToDate', () async {
      final result = await serviceOf(
        api: apiOf('v0.9.0'),
        version: '0.9.0',
      ).check();

      expect(result, isA<UpdateUpToDate>());
    });

    test('本地版本领先 release → failed', () async {
      final result = await serviceOf(
        api: apiOf('v0.8.0'),
        version: '0.9.0',
      ).check();

      expect(result, isA<UpdateCheckFailed>());
    });

    test('tag 格式非法 → failed', () async {
      final result = await serviceOf(
        api: apiOf('not-a-version'),
        version: '0.9.0',
      ).check();

      expect(result, isA<UpdateCheckFailed>());
    });

    test('API 请求异常 → failed', () async {
      final result = await serviceOf(
        api: FailingApi(Exception('网络异常')),
        version: '0.9.0',
      ).check();

      expect(result, isA<UpdateCheckFailed>());
    });

    test('本地版本信息读取失败 → failed', () async {
      final result = await UpdateService(
        api: apiOf('v1.0.0'),
        packageInfoLoader: () async => throw Exception('插件异常'),
      ).check();

      expect(result, isA<UpdateCheckFailed>());
    });
  });
}

/// 固定返回的 fake API（super 构造不发起任何真实请求）
class FakeApi extends GitHubReleaseApi {
  FakeApi(this.release) : super(client: _UnusedClient());

  final ReleaseInfo release;

  @override
  Future<ReleaseInfo> fetchLatest() async => release;
}

/// 固定抛错的 fake API
class FailingApi extends GitHubReleaseApi {
  FailingApi(this.error) : super(client: _UnusedClient());

  final Object error;

  @override
  Future<ReleaseInfo> fetchLatest() async => throw error;
}

/// 占位客户端：fake 不走 HTTP，仅需满足构造参数
class _UnusedClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
