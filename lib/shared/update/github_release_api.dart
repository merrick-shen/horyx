import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:horyx/shared/update/models/release_info.dart';

/// GitHub Release API 请求异常
/// 网络、超时、非 200、响应解析失败统一归入，调用方据此提示「检查失败」
class GitHubReleaseApiException implements Exception {
  const GitHubReleaseApiException(this.message);

  final String message;

  @override
  String toString() => 'GitHubReleaseApiException: $message';
}

/// GitHub Release API 客户端
/// 沿用项目零第三方网络依赖约定，基于 dart:io HttpClient 实现
class GitHubReleaseApi {
  GitHubReleaseApi({HttpClient? client, this.timeout = defaultTimeout})
    : _client = client ?? HttpClient();

  /// 当前为开发测试仓库，正式发布前切回 merrick-shen/horyx
  static const repoOwner = 'merrick-shen';
  static const repoName = 'update-test';

  /// 请求全程超时（国内直连 GitHub 可能长时间无响应，需兜底）
  static const defaultTimeout = Duration(seconds: 10);

  final HttpClient _client;

  /// 单步超时时长（连接、响应、读体各步共用）
  final Duration timeout;

  /// 查询仓库最新正式 Release
  /// 仅返回最新正式版（draft / prerelease 由端点自动排除）；
  /// 非 200（含仓库无 Release 的 404）一律抛 [GitHubReleaseApiException]
  Future<ReleaseInfo> fetchLatest() async {
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
      );
      final request = await _client
          .getUrl(uri)
          .timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw GitHubReleaseApiException('HTTP ${response.statusCode}');
      }
      final body = await response.transform(utf8.decoder).join().timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw GitHubReleaseApiException('响应不是 JSON 对象');
      }
      return ReleaseInfo.fromJson(decoded);
    } on GitHubReleaseApiException {
      rethrow;
    } catch (e) {
      // 超时、Socket 异常、坏 JSON 等统一归类，不向上抛裸异常
      throw GitHubReleaseApiException('检查更新请求失败: $e');
    }
  }
}
