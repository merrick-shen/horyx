import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/widgets/app_page_scaffold.dart';
import 'package:horyx/shared/widgets/info_list_view.dart';

// ---------------------------------------------------------------------------
// 开源许可声明页：列表页 + 详情页 + 数据层
// 数据全部来自运行时 LicenseRegistry（框架自动注册实际打包的依赖，
// 含传递依赖），不手工维护清单；
// 视觉与动效与更新日志页保持一致
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
/// 注意这是启发式匹配，不作为法律依据。
/// 引擎原生三方库（zlib/OpenSSL/IJG 等）与字体许可（SIL OFL）不在宽松许可
/// 常见模式内，需单独覆盖；特定许可的判定须排在 BSD 通用条款之前，
/// 避免它们文中的相似条款被误判为 BSD（如 OpenSSL 的类 BSD 排版）
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
  // 以下许可文本含类 BSD 的「redistribution and use」条款，须先于 BSD 兜底判定
  if (t.contains('this product includes software developed by the openssl')) {
    return 'OpenSSL';
  }
  if (t.contains('alteration of the sources') && t.contains('as-is')) {
    return 'zlib';
  }
  if (t.contains('independent jpeg group')) return 'IJG';
  if (t.contains('open font license')) return 'SIL OFL';
  if (t.contains('boost software license')) return 'Boost';
  if (t.contains('redistribution and use in source and binary forms')) {
    // 含「不得用贡献者名义背书」第三条款判定为 3 条款，否则 2 条款
    return t.contains('neither the name') ? 'BSD-3-Clause' : 'BSD-2-Clause';
  }
  // Lesser/Affero 文中也会出现「gnu general public license」字样，须先于 GPL 判定
  if (t.contains('gnu lesser general public license')) return 'LGPL';
  if (t.contains('gnu affero general public license')) return 'AGPL';
  if (t.contains('gnu general public license')) return 'GPL';
  if (t.contains('mozilla public license')) return 'MPL-2.0';
  return null;
}

/// 提取版权行作为列表摘要：优先取含 Copyright / © 的行（不分大小写）；
/// 全文无版权声明时兜底取首个非空行（zlib/OpenSSL 等引擎原生库许可
/// 的版权行常嵌在段落中，此时以许可开头的第一行作摘要仍优于留空）
String? extractCopyrightLine(String fullText) {
  String? firstNonEmpty;
  for (final line in fullText.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    firstNonEmpty ??= trimmed;
    if (trimmed.toLowerCase().startsWith('copyright') ||
        trimmed.startsWith('©')) {
      return trimmed;
    }
  }
  return firstNonEmpty;
}

// ---------------------------------------------------------------------------
// 页面 UI
// ---------------------------------------------------------------------------

/// 开源许可列表页：包名 + 许可证类型 + 版权行摘要，点击进入全文详情页
class OssLicensesPage extends StatefulWidget {
  const OssLicensesPage({super.key});

  @override
  State<OssLicensesPage> createState() => _OssLicensesPageState();
}

class _OssLicensesPageState extends State<OssLicensesPage> {
  /// 许可列表；null 表示加载中，空列表表示无内容
  List<OssLicense>? _licenses;

  @override
  void initState() {
    super.initState();
    _loadLicenses();
  }

  /// 收集运行时注册的全部开源许可
  Future<void> _loadLicenses() async {
    final licenses = await collectOssLicenses();
    if (mounted) setState(() => _licenses = licenses);
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: '开源许可',
      showBack: true,
      // 列表样式、加载/空态与点击交互统一由通用组件 InfoListView 承载
      child: InfoListView(
        items: _licenses?.map(_toListItem).toList(),
        emptyText: '暂无开源许可信息',
      ),
    );
  }

  /// 将许可数据映射为通用列表条目；fullText 仅计算一次供类型识别与摘要复用
  InfoListItem _toListItem(OssLicense license) {
    final fullText = license.fullText;
    return InfoListItem(
      title: license.package,
      trailing: detectLicenseType(fullText),
      subtitle: extractCopyrightLine(fullText),
      // 与详情页大标题建立 Hero 共享元素过渡
      heroTag: 'oss-license-${license.package}',
      onTap: () => Navigator.of(context).push(_OssLicenseDetailRoute(license)),
    );
  }
}

/// 许可详情页路由：淡入 + 轻微上滑的平滑过渡
/// 时长与曲线与更新日志详情页一致（300ms easeOutCubic），保持全局动效统一
class _OssLicenseDetailRoute extends PageRouteBuilder<void> {
  _OssLicenseDetailRoute(OssLicense license)
      : super(
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          pageBuilder: (context, animation, secondaryAnimation) =>
              _OssLicenseDetailPage(license: license),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}

/// 许可详情页：包名大标题（Hero 目标）+ 类型标签 + 许可证全文
class _OssLicenseDetailPage extends StatelessWidget {
  const _OssLicenseDetailPage({required this.license});

  final OssLicense license;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = detectLicenseType(license.fullText);

    return AppPageScaffold(
      title: '开源许可',
      showBack: true,
      child: Scrollbar(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            // 大号包名标题，承接列表卡片飞入的 Hero 过渡
            Hero(
              tag: 'oss-license-${license.package}',
              child: Material(
                type: MaterialType.transparency,
                child: Text(
                  license.package,
                  style: TextStyle(
                    color: palette.primary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (type != null) ...[
              const SizedBox(height: 8),
              // 许可证类型标签：主题色淡底小徽章
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    type,
                    style: TextStyle(
                      color: palette.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            // 一个包可能对应多条许可证，依次渲染，条目间留白分隔
            for (var i = 0; i < license.entries.length; i++) ...[
              if (i > 0) const SizedBox(height: 24),
              ...license.entries[i].paragraphs.map(
                (p) => _buildParagraph(palette, p),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 单个许可证段落：居中段（多为标题行）加粗居中，其余按级别左缩进
  Widget _buildParagraph(AppPalette palette, LicenseParagraph paragraph) {
    final centered = paragraph.indent == LicenseParagraph.centeredIndent;
    return Padding(
      padding: EdgeInsets.only(
        left: centered ? 0 : paragraph.indent * 16.0,
        bottom: 8,
      ),
      child: Text(
        paragraph.text,
        textAlign: centered ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          color: centered ? palette.textPrimary : palette.textSecondary,
          fontSize: 13,
          fontWeight: centered ? FontWeight.w700 : FontWeight.w400,
          height: 1.5,
        ),
      ),
    );
  }
}
