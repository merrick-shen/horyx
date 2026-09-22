import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/shared/update/changelog_parser.dart';

void main() {
  group('parseChangelogDocument（整份 CHANGELOG.md）', () {
    const document = '''
# Changelog

格式说明行，应被跳过

## [0.10.0] - 2026-09-16

### Added

- 新功能一
- 新功能二
  - 子项甲
  - 子项乙

### Fixed

- 修复一

## [Unreleased]

（空版本节，不应生成条目）

## [0.9.0] - 2026-09-12

### Changed

- 变更一
''';

    test('跳过文件头模板声明，从首个版本节开始解析', () {
      final versions = parseChangelogDocument(document);
      expect(versions, hasLength(2));
      expect(versions[0].version, '0.10.0');
      expect(versions[1].version, '0.9.0');
    });

    test('版本号与发布日期正确提取，Unreleased 映射为「未发布」', () {
      final versions = parseChangelogDocument(document);
      expect(versions[0].date, '2026-09-16');
      expect(versions[0].sections.map((s) => s.typeName), ['新增', '修复']);
    });

    test('主项与缩进子项正确归组', () {
      final versions = parseChangelogDocument(document);
      final added = versions[0].sections.first;
      expect(added.items, hasLength(2));
      expect(added.items[0].text, '新功能一');
      expect(added.items[0].children, isEmpty);
      expect(added.items[1].children, ['子项甲', '子项乙']);
    });

    test('空版本节（无任何类型分组）被过滤', () {
      final versions = parseChangelogDocument(document);
      expect(versions.map((v) => v.version), isNot(contains('未发布')));
    });
  });

  group('parseChangelogSections（Release 正文）', () {
    test('解析 CRLF 换行的版本段（GitHub Release 实际格式）', () {
      final sections = parseChangelogSections(
        '## [0.10.0] - 2026-09-16\r\n\r\n'
        '### Added\r\n\r\n'
        '- 新功能一\r\n'
        '- 新功能二\r\n\r\n'
        '### Fixed\r\n\r\n'
        '- 修复一\r\n',
      );
      expect(sections, hasLength(2));
      expect(sections[0].typeName, '新增');
      expect(sections[0].items.map((i) => i.text), ['新功能一', '新功能二']);
      expect(sections[1].typeName, '修复');
    });

    test('未映射的英文类型名原样保留', () {
      final sections = parseChangelogSections('### Security\n\n- 加固一\n');
      expect(sections.single.typeName, 'Security');
    });

    test('无结构化内容时返回空列表（调用方回退纯文本渲染）', () {
      expect(parseChangelogSections('只是一段普通说明文字'), isEmpty);
      expect(parseChangelogSections(''), isEmpty);
    });

    test('分组前的列表项被忽略而非崩溃', () {
      final sections = parseChangelogSections('- 无分组条目\n\n### Added\n- 有效条目\n');
      expect(sections, hasLength(1));
      expect(sections.single.items.single.text, '有效条目');
    });
  });
}
