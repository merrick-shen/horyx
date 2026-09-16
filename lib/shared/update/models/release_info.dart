/// GitHub Release 信息模型
/// 仅解析更新检测所需字段，不做冗余字段留存
class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.downloadUrl,
  });

  /// 版本标签（如 v0.9.0，可能不带 v 前缀）
  final String tagName;

  /// 发布标题（弹窗展示，可能为空）
  final String name;

  /// Release 说明（弹窗正文，可能为空）
  final String body;

  /// Release 页面地址（跳转兜底目标）
  final String htmlUrl;

  /// 下载地址：取第一个 .apk 资产直链，缺失时回退 Release 页面
  final String downloadUrl;

  /// 解析 API 响应；字段缺失或类型不符时置空串，保证解析不抛异常
  /// （空 tag 后续版本比较会自然判为无新版本，无需在此校验）
  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    String asString(dynamic value) => value is String ? value : '';

    // 优先取第一个 .apk 资产的直链；无资产或无 .apk 时回退 Release 页面
    var downloadUrl = '';
    final assets = json['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map) continue;
        final assetName = asString(asset['name']);
        if (!assetName.toLowerCase().endsWith('.apk')) continue;
        final url = asString(asset['browser_download_url']);
        if (url.isNotEmpty) {
          downloadUrl = url;
          break;
        }
      }
    }
    final htmlUrl = asString(json['html_url']);
    downloadUrl = downloadUrl.isEmpty ? htmlUrl : downloadUrl;

    return ReleaseInfo(
      tagName: asString(json['tag_name']),
      name: asString(json['name']),
      body: asString(json['body']),
      htmlUrl: htmlUrl,
      downloadUrl: downloadUrl,
    );
  }
}
