import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/shared/update/github_release_api.dart';

/// GitHubReleaseApi 测试：注入 mock HttpClient，不发真实网络请求
void main() {
  // 与 GitHubReleaseApi 内的仓库常量保持一致（当前为测试仓库）
  const latestUrl =
      'https://api.github.com/repos/merrick-shen/update-test/releases/latest';

  /// 标准响应体：含一个 APK 资产
  const fullBody = '''
  {
    "tag_name": "v0.10.0",
    "name": "0.10.0",
    "body": "修复若干问题",
    "html_url": "https://github.com/merrick-shen/update-test/releases/tag/v0.10.0",
    "assets": [
      {"name": "README.md", "browser_download_url": "https://example.com/README.md"},
      {"name": "horyx-v0.10.0.apk", "browser_download_url": "https://example.com/app.apk"}
    ]
  }
  ''';

  GitHubReleaseApi buildApi(HttpClient client, {Duration? timeout}) =>
      GitHubReleaseApi(
        client: client,
        timeout: timeout ?? GitHubReleaseApi.defaultTimeout,
      );

  group('fetchLatest 成功路径', () {
    test('请求 URL 与 Accept 头正确，字段解析正确', () async {
      final client = _MockHttpClient(_MockHttpResponse(200, fullBody));
      final release = await buildApi(client).fetchLatest();

      expect(client.lastUrl.toString(), latestUrl);
      expect(client.headers['accept'], 'application/vnd.github+json');
      expect(release.tagName, 'v0.10.0');
      expect(release.name, '0.10.0');
      expect(release.body, '修复若干问题');
      expect(
        release.htmlUrl,
        'https://github.com/merrick-shen/update-test/releases/tag/v0.10.0',
      );
      expect(release.downloadUrl, 'https://example.com/app.apk');
    });

    test('无 assets 时下载地址回退 Release 页面', () async {
      const body = '''
      {"tag_name": "v0.10.0", "html_url": "https://example.com/release"}
      ''';
      final client = _MockHttpClient(_MockHttpResponse(200, body));
      final release = await buildApi(client).fetchLatest();

      expect(release.downloadUrl, 'https://example.com/release');
    });

    test('assets 中无 .apk 时同样回退 Release 页面', () async {
      const body = '''
      {
        "tag_name": "v0.10.0",
        "html_url": "https://example.com/release",
        "assets": [{"name": "README.md", "browser_download_url": "https://example.com/README.md"}]
      }
      ''';
      final client = _MockHttpClient(_MockHttpResponse(200, body));
      final release = await buildApi(client).fetchLatest();

      expect(release.downloadUrl, 'https://example.com/release');
    });

    test('字段缺失或类型异常不崩溃，置空串', () async {
      const body = '{"tag_name": 123, "assets": "oops", "body": null}';
      final client = _MockHttpClient(_MockHttpResponse(200, body));
      final release = await buildApi(client).fetchLatest();

      expect(release.tagName, '');
      expect(release.name, '');
      expect(release.body, '');
      expect(release.htmlUrl, '');
      expect(release.downloadUrl, '');
    });
  });

  group('fetchLatest 失败路径（统一抛 GitHubReleaseApiException）', () {
    test('非 200（含 404 无 Release）抛异常', () async {
      final api404 = buildApi(_MockHttpClient(_MockHttpResponse(404, '{}')));
      await expectLater(api404.fetchLatest(), throwsA(isA<GitHubReleaseApiException>()));

      final api500 = buildApi(_MockHttpClient(_MockHttpResponse(500, 'oops')));
      await expectLater(api500.fetchLatest(), throwsA(isA<GitHubReleaseApiException>()));
    });

    test('坏 JSON 抛异常', () async {
      final client = _MockHttpClient(_MockHttpResponse(200, 'not json'));
      await expectLater(
        buildApi(client).fetchLatest(),
        throwsA(isA<GitHubReleaseApiException>()),
      );
    });

    test('响应非 JSON 对象抛异常', () async {
      final client = _MockHttpClient(_MockHttpResponse(200, '[1, 2]'));
      await expectLater(
        buildApi(client).fetchLatest(),
        throwsA(isA<GitHubReleaseApiException>()),
      );
    });

    test('连接异常（如断网）抛异常', () async {
      final client = _FailingHttpClient(const SocketException('断网'));
      await expectLater(
        buildApi(client).fetchLatest(),
        throwsA(isA<GitHubReleaseApiException>()),
      );
    });

    test('响应超时抛异常', () async {
      final client = _MockHttpClient(
        _MockHttpResponse(200, fullBody),
        delay: const Duration(milliseconds: 200),
      );
      await expectLater(
        buildApi(client, timeout: const Duration(milliseconds: 50)).fetchLatest(),
        throwsA(isA<GitHubReleaseApiException>()),
      );
    });
  });
}

/// 固定响应的 mock HttpClient（未涉及的接口成员经 noSuchMethod 跳过）
class _MockHttpClient implements HttpClient {
  _MockHttpClient(this.response, {this.delay = Duration.zero});

  final HttpClientResponse response;
  final Duration delay;

  Uri? lastUrl;
  final headers = <String, String>{};

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    lastUrl = url;
    await Future<void>.delayed(delay);
    return _MockHttpRequest(response, _MockHttpHeaders(headers));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

///getUrl 必抛异常的 mock（模拟断网）
class _FailingHttpClient implements HttpClient {
  _FailingHttpClient(this.error);

  final Object error;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => throw error;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpRequest implements HttpClientRequest {
  _MockHttpRequest(this.response, this.headers);

  final HttpClientResponse response;

  @override
  final HttpHeaders headers;

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 可记录 set 调用的 mock HttpHeaders
class _MockHttpHeaders implements HttpHeaders {
  _MockHttpHeaders(this.values);

  final Map<String, String> values;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 固定状态码与响应体的 mock HttpClientResponse（本身是字节流）
class _MockHttpResponse extends Stream<List<int>> implements HttpClientResponse {
  _MockHttpResponse(this.statusCode, this.body);

  @override
  final int statusCode;
  final String body;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> data)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(utf8.encode(body)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
