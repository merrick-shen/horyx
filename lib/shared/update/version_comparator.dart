/// 版本关系（更新检测判定依据）
enum VersionRelation {
  /// release 版本新于当前版本
  newer,

  /// release 与当前版本相同
  same,

  /// release 版本旧于当前版本（本地领先）
  older,

  /// 任一版本号格式非法
  invalid,
}

/// 语义化版本号比较（纯静态逻辑，无 IO，仅用于更新检测）
///
/// 仅提供中性比较结果，业务归类由调用方决定：
/// newer → 有新版本；same → 无新版本；older / invalid → 检查失败
class VersionComparator {
  const VersionComparator._();

  /// 解析版本号为整数段列表
  /// 兼容 `v`/`V` 前缀与 `+build` 后缀（忽略）；任一段非数字视为非法返回 null
  static List<int>? _parse(String version) {
    var text = version.trim();
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }
    // build 元数据不参与比较（tag 端约定 v主.次.补，此处仅容错）
    final plusIndex = text.indexOf('+');
    if (plusIndex != -1) {
      text = text.substring(0, plusIndex);
    }
    if (text.isEmpty) return null;
    final segments = <int>[];
    for (final part in text.split('.')) {
      final value = int.tryParse(part);
      if (value == null) return null;
      segments.add(value);
    }
    return segments;
  }

  /// 比较 [releaseTag] 与 [currentVersion]
  /// 逐段比较、缺段补 0（如 1.0 与 1.0.0 等价）；任一非法返回 [VersionRelation.invalid]
  static VersionRelation compare(String releaseTag, String currentVersion) {
    final release = _parse(releaseTag);
    final current = _parse(currentVersion);
    if (release == null || current == null) return VersionRelation.invalid;
    final length = release.length > current.length
        ? release.length
        : current.length;
    for (var i = 0; i < length; i++) {
      final r = i < release.length ? release[i] : 0;
      final c = i < current.length ? current[i] : 0;
      if (r != c) {
        return r > c ? VersionRelation.newer : VersionRelation.older;
      }
    }
    return VersionRelation.same;
  }
}
