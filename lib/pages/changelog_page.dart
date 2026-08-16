import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../theme/app_theme.dart';
import '../widgets/app_top_bar.dart';

/// 更新日志页
/// 内容直接读取打包进应用的 CHANGELOG.md 资源，与仓库文件保持一致：
/// 后续更新 CHANGELOG.md 后重新构建即可同步，无需在代码中维护第二份数据
class ChangelogPage extends StatefulWidget {
  const ChangelogPage({super.key});

  @override
  State<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<ChangelogPage> {
  /// 解析后的版本列表；null 表示加载中，空列表表示无内容
  List<_VersionSection>? _versions;

  @override
  void initState() {
    super.initState();
    _loadChangelog();
  }

  /// 读取并解析 CHANGELOG.md
  /// 资源随应用打包，正常不会失败；异常时置空列表展示占位文案，避免崩溃
  Future<void> _loadChangelog() async {
    try {
      final text = await rootBundle.loadString('CHANGELOG.md');
      if (mounted) setState(() => _versions = _parse(text));
    } catch (_) {
      if (mounted) setState(() => _versions = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 顶栏 + 返回按钮（与各二级页一致）
            AppTopBar(
              title: '更新日志',
              leading: IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: palette.textPrimary,
                  size: 20,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Expanded(
              child: _buildBody(palette),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppPalette palette) {
    if (_versions == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_versions!.isEmpty) {
      return Center(
        child: Text(
          '暂无更新内容',
          style: TextStyle(color: palette.textSecondary, fontSize: 14),
        ),
      );
    }
    return Scrollbar(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        itemCount: _versions!.length,
        itemBuilder: (context, index) =>
            _buildVersion(palette, _versions![index]),
      ),
    );
  }

  /// 单个版本区块：版本头 + 各类型分组
  Widget _buildVersion(AppPalette palette, _VersionSection version) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (version.date != null) ...[
          // 版本号 + 发布日期
          Row(
            children: [
              Text(
                'v${version.version}',
                style: TextStyle(
                  color: palette.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                version.date!,
                style: TextStyle(color: palette.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ] else ...[
          // 未发布版本无日期
          Text(
            version.version,
            style: TextStyle(
              color: palette.primary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
        ...version.sections.expand((section) => [
              const SizedBox(height: 14),
              Text(
                section.typeName,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ...section.items.map((item) => _buildItem(palette, item)),
            ]),
      ],
    );
  }

  /// 单条变更记录：主项 + 可选子项（如四个游戏的明细）
  Widget _buildItem(AppPalette palette, _ChangelogItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 品牌色小圆点作为主列表符号
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(top: 7),
                decoration: BoxDecoration(
                  color: palette.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.text,
                  style: TextStyle(color: palette.textPrimary, fontSize: 13.5),
                ),
              ),
            ],
          ),
          // 子项：整体左缩进，符号用浅色小圆点与主项区分层级
          ...item.children.map(
            (child) => Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: palette.textSecondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      child,
                      style:
                          TextStyle(color: palette.textSecondary, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CHANGELOG.md 解析（Keep a Changelog 1.1.0 固定结构：## 版本 / ### 类型 / - 列表）
// ---------------------------------------------------------------------------

/// Keep a Changelog 类型标题的中文映射，界面统一中文展示
const _typeNames = {
  'Added': '新增',
  'Changed': '变更',
  'Deprecated': '废弃',
  'Removed': '移除',
  'Fixed': '修复',
  'Security': '安全',
};

/// 解析 CHANGELOG.md 文本为版本列表
/// 跳过文件头部模板声明（# 标题与格式说明），从首个 ## 版本节开始；
/// 空版本节（如空的 [Unreleased]）不生成条目，避免渲染空标题
List<_VersionSection> _parse(String text) {
  final versions = <_VersionSection>[];
  _VersionSection? version;
  _TypeSection? section;

  for (final rawLine in text.split('\n')) {
    // 只去除行尾空白，保留行首缩进用于区分子列表项
    final line = rawLine.trimRight();
    if (line.startsWith('## ')) {
      version = _parseVersionHeader(line.substring(3));
      section = null;
      if (version != null) versions.add(version);
    } else if (line.startsWith('### ') && version != null) {
      final typeName = line.substring(4).trim();
      // 新建分组后 section 已提升为非空，无需 ! 断言
      section = _TypeSection(_typeNames[typeName] ?? typeName);
      version.sections.add(section);
    } else if (line.startsWith('  - ') && section != null && section.items.isNotEmpty) {
      // 缩进两个空格的列表项归入上一条主项作为子项
      section.items.last.children.add(line.substring(4).trim());
    } else if (line.startsWith('- ') && section != null) {
      section.items.add(_ChangelogItem(line.substring(2).trim()));
    }
  }
  // 过滤没有任何类型分组的版本节（如暂无内容的 [Unreleased]）
  return versions.where((v) => v.sections.isNotEmpty).toList();
}

/// 解析版本节标题，如 "[1.0.0] - 2026-08-17" / "[Unreleased]"
_VersionSection? _parseVersionHeader(String body) {
  final match =
      RegExp(r'^\[(.+?)\](?:\s*-\s*(.+))?$').firstMatch(body.trim());
  if (match == null) return null;
  final name = match.group(1)!;
  return _VersionSection(
    name == 'Unreleased' ? '未发布' : name,
    date: match.group(2),
  );
}

/// 单个版本节（对应一个 ## 标题）
class _VersionSection {
  final String version;
  final String? date;
  final List<_TypeSection> sections = [];

  _VersionSection(this.version, {this.date});
}

/// 版本下的类型分组（对应一个 ### 标题）
class _TypeSection {
  final String typeName;
  final List<_ChangelogItem> items = [];

  _TypeSection(this.typeName);
}

/// 一条变更记录（可带子项）
class _ChangelogItem {
  final String text;
  final List<String> children = [];

  _ChangelogItem(this.text);
}
