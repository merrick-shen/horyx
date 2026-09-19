import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// 开源许可数据层：包名聚合 + 许可证类型识别 + 版权行提取
// 数据全部来自运行时 LicenseRegistry（框架自动注册实际打包的依赖，
// 含传递依赖），不手工维护清单；本文件当前仅含数据层，
// 列表页与详情页 UI 在后续步骤中补充
// ---------------------------------------------------------------------------

/// 单个开源包的许可信息（按包名聚合其名下所有许可证条目）
class OssLicense {
  OssLicense({required this.package, required this.entries});

  /// 包名（如 flame）
  final String package;

  /// 该包名下注册的所有许可证条目（一个包可能对应多条）
  final List<LicenseEntry> entries;

  /// 许可证全文（多条拼接，用于类型识别与版权行提取）
  String get fullText => entries
      .expand((e) => e.paragraphs)
      .map((p) => p.text)
      .join('\n');
}

/// 收集运行时注册的全部开源许可，按包名聚合后升序返回（不区分大小写）
/// 异常时返回空列表，页面据此走空态兜底（与更新日志页约定一致）；
/// paragraphs 解析有一定开销（数十个包），如实测卡顿可改用 compute 移入 isolate
Future<List<OssLicense>> collectOssLicenses() async {
  try {
    final byPackage = <String, List<LicenseEntry>>{};
    await for (final entry in LicenseRegistry.licenses) {
      for (final pkg in entry.packages) {
        byPackage.putIfAbsent(pkg, () => []).add(entry);
      }
    }
    final names = byPackage.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [
      for (final name in names) OssLicense(package: name, entries: byPackage[name]!),
    ];
  } catch (_) {
    return const [];
  }
}

/// 从许可证正文识别类型，仅作列表标签展示；识别不出返回 null（以详情页全文为准）。
/// 注意这是启发式匹配，不作为法律依据
String? detectLicenseType(String text) {
  final t = text.toLowerCase();
  if (t.contains('mit license') ||
      t.contains('permission is hereby granted, free of charge')) {
    return 'MIT';
  }
  if (t.contains('apache license') && t.contains('version 2.0')) {
    return 'Apache-2.0';
  }
  if (t.contains('bsd 3-clause')) return 'BSD-3-Clause';
  if (t.contains('redistribution and use in source and binary forms')) {
    // 含「不得用贡献者名义背书」第三条款判定为 3 条款，否则 2 条款
    return t.contains('neither the name') ? 'BSD-3-Clause' : 'BSD-2-Clause';
  }
  if (t.contains('gnu general public license')) return 'GPL';
  if (t.contains('mozilla public license')) return 'MPL-2.0';
  return null;
}

/// 提取版权行作为列表摘要：取首个以 Copyright / © 开头的非空行；
/// 正文无版权声明时返回 null（避免把许可证正文首句误当摘要）
String? extractCopyrightLine(String fullText) {
  for (final line in fullText.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('Copyright') || trimmed.startsWith('©')) {
      return trimmed;
    }
  }
  return null;
}
