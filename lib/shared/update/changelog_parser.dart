/// Keep a Changelog 1.1.0 格式解析（固定结构：## 版本 / ### 类型 / - 列表）
/// 更新日志页（整份 CHANGELOG.md）与更新弹窗（GitHub Release 说明）共用：
/// 两处内容本就同源，解析规则只在此一处维护，保证行为一致
library;

/// Keep a Changelog 类型标题的中文映射，界面统一中文展示
const changelogTypeNames = {
  'Added': '新增',
  'Changed': '变更',
  'Fixed': '修复',
  'Removed': '移除',
};

/// 一条变更记录（可带缩进子项）
class ChangelogItem {
  ChangelogItem(this.text);

  final String text;
  final List<String> children = [];
}

/// 一个类型分组（对应一个 ### 标题）
class ChangelogSection {
  ChangelogSection(this.typeName);

  final String typeName;
  final List<ChangelogItem> items = [];
}

/// 一个版本节（对应一个 ## 标题）
class ChangelogVersion {
  ChangelogVersion(this.version, {this.date});

  final String version;
  final String? date;
  final List<ChangelogSection> sections = [];
}

/// 解析整份 CHANGELOG.md 文档为版本列表
/// 跳过文件头部模板声明（# 标题与格式说明），从首个 ## 版本节开始；
/// 空版本节（如空的 [Unreleased]）不生成条目，避免渲染空标题
List<ChangelogVersion> parseChangelogDocument(String text) {
  final versions = <ChangelogVersion>[];
  // 按 "## " 切分：首段为文件头模板声明，跳过
  final blocks = text.split(RegExp('^## ', multiLine: true)).skip(1);
  for (final block in blocks) {
    final lines = block.split('\n');
    final version = _parseVersionHeader(lines.first);
    if (version == null) continue;
    version.sections.addAll(_parseSections(lines.skip(1)));
    if (version.sections.isNotEmpty) versions.add(version);
  }
  return versions;
}

/// 解析更新说明正文（GitHub Release body）为类型分组列表
/// Release 说明通常直接粘贴 CHANGELOG 版本段，可能带 ## 版本标题行，跳过即可；
/// 正文不含任何 "### / - " 结构时返回空列表，调用方据此回退纯文本渲染
List<ChangelogSection> parseChangelogSections(String text) {
  return _parseSections(text.split('\n'));
}

/// 从行流解析类型分组：### 开新分组、- 为主项、两空格缩进的 - 为子项
/// 其余行（## 版本标题、空行、普通段落）不参与结构化渲染
List<ChangelogSection> _parseSections(Iterable<String> rawLines) {
  final sections = <ChangelogSection>[];
  for (final rawLine in rawLines) {
    // 只去除行尾空白（含 CRLF 的 \r），保留行首缩进用于区分子列表项
    final line = rawLine.trimRight();
    if (line.startsWith('### ')) {
      final typeName = line.substring(4).trim();
      sections.add(ChangelogSection(changelogTypeNames[typeName] ?? typeName));
    } else if (line.startsWith('  - ') &&
        sections.isNotEmpty &&
        sections.last.items.isNotEmpty) {
      // 缩进两个空格的列表项归入上一条主项作为子项
      sections.last.items.last.children.add(line.substring(4).trim());
    } else if (line.startsWith('- ') && sections.isNotEmpty) {
      sections.last.items.add(ChangelogItem(line.substring(2).trim()));
    }
  }
  return sections;
}

/// 解析版本节标题，如 "[1.0.0] - 2026-08-17" / "[Unreleased]"
ChangelogVersion? _parseVersionHeader(String body) {
  final match =
      RegExp(r'^\[(.+?)\](?:\s*-\s*(.+))?$').firstMatch(body.trim());
  if (match == null) return null;
  final name = match.group(1)!;
  return ChangelogVersion(
    name == 'Unreleased' ? '未发布' : name,
    date: match.group(2),
  );
}
