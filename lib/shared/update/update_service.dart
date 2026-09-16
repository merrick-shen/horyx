import 'package:package_info_plus/package_info_plus.dart';

import 'package:horyx/shared/update/github_release_api.dart';
import 'package:horyx/shared/update/models/release_info.dart';
import 'package:horyx/shared/update/version_comparator.dart';

/// 更新检查结果：sealed 三态，UI 层 switch 穷举、零额外判断
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// 有新版本：携带 Release 详情（弹窗展示版本号、说明与下载地址）
class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable(this.release);

  final ReleaseInfo release;
}

/// 无新版本：release 与当前版本完全相同
class UpdateUpToDate extends UpdateCheckResult {
  const UpdateUpToDate();
}

/// 检查失败（网络异常、超时、非 200、本地版本领先、tag 格式非法等，
/// 除「新于」「相同」外的其余一切情况，用户可见提示）
class UpdateCheckFailed extends UpdateCheckResult {
  const UpdateCheckFailed();
}

/// 更新检查服务：组合当前应用版本与 GitHub 最新 Release 判定
class UpdateService {
  UpdateService({
    GitHubReleaseApi? api,
    Future<PackageInfo> Function()? packageInfoLoader,
  }) : _api = api ?? GitHubReleaseApi(),
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform;

  final GitHubReleaseApi _api;

  /// 版本信息加载器可注入，便于单元测试脱离平台插件
  final Future<PackageInfo> Function() _packageInfoLoader;

  /// 执行一次检查；除「新于」「相同」外的其余情况统一归为 [UpdateCheckFailed]
  Future<UpdateCheckResult> check() async {
    try {
      final info = await _packageInfoLoader();
      final release = await _api.fetchLatest();
      switch (VersionComparator.compare(release.tagName, info.version)) {
        case VersionRelation.newer:
          return UpdateAvailable(release);
        case VersionRelation.same:
          return const UpdateUpToDate();
        case VersionRelation.older:
        case VersionRelation.invalid:
          return const UpdateCheckFailed();
      }
    } catch (_) {
      return const UpdateCheckFailed();
    }
  }
}
