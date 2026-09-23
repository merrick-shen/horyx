import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/app/pages/settings/oss_licenses_page.dart';

void main() {
  // detectLicenseType 是开源许可页列表标签的唯一判定来源，为纯函数、
  // 无外部依赖，直接对启发式规则逐条验证（含判定顺序敏感性）
  group('detectLicenseType 许可类型识别', () {
    test('MIT：显式标题或特征授权句均可识别', () {
      expect(detectLicenseType('MIT License'), 'MIT');
      expect(
        detectLicenseType(
          'Permission is hereby granted, free of charge, to any person '
          'obtaining a copy of this software.',
        ),
        'MIT',
      );
    });

    test('Apache-2.0：须同时命中标题与版本号，缺一不判定', () {
      expect(detectLicenseType('Apache License\nVersion 2.0'), 'Apache-2.0');
      expect(detectLicenseType('Apache License'), isNull);
    });

    test('BSD-3-Clause：显式 3-clause 标题', () {
      expect(detectLicenseType('BSD 3-Clause License'), 'BSD-3-Clause');
    });

    test('OpenSSL：文含类 BSD 条款也不得误判为 BSD（验证判定顺序）', () {
      const text = 'This product includes software developed by the OpenSSL '
          'Project for use in the OpenSSL Toolkit.\n'
          'Redistribution and use in source and binary forms, with or '
          'without modification, are permitted.';
      expect(detectLicenseType(text), 'OpenSSL');
    });

    test('zlib：须同时命中特征句与 as-is，单特征不判定', () {
      expect(
        detectLicenseType('alteration of the sources ... provided as-is'),
        'zlib',
      );
      expect(detectLicenseType('alteration of the sources'), isNull);
    });

    test('IJG / SIL OFL / Boost：独立特征命中', () {
      expect(detectLicenseType('Independent JPEG Group'), 'IJG');
      expect(detectLicenseType('OPEN FONT LICENSE'), 'SIL OFL');
      expect(detectLicenseType('Boost Software License'), 'Boost');
    });

    test('BSD 通用条款：含「neither the name」判 3 条款，否则 2 条款', () {
      const clause = 'Redistribution and use in source and binary forms, '
          'with or without modification, are permitted.';
      expect(
        detectLicenseType('$clause\nNeither the name of the author may be '
            'used to endorse derived products.'),
        'BSD-3-Clause',
      );
      expect(detectLicenseType(clause), 'BSD-2-Clause');
    });

    test('LGPL/AGPL 优先于 GPL：全文引用 GPL 名称时仍正确区分', () {
      // 模拟 LGPL/AGPL 全文的常见形态：正文同时出现自身标题与 GPL 名称，
      // 判定顺序保证先命中前者
      expect(
        detectLicenseType(
          'GNU LESSER GENERAL PUBLIC LICENSE\n...refer to the GNU General '
          'Public License from time to time...',
        ),
        'LGPL',
      );
      expect(
        detectLicenseType(
          'GNU AFFERO GENERAL PUBLIC LICENSE\n...under the terms of the GNU '
          'General Public License...',
        ),
        'AGPL',
      );
    });

    test('GPL / MPL：常规标题命中', () {
      expect(detectLicenseType('GNU GENERAL PUBLIC LICENSE'), 'GPL');
      expect(detectLicenseType('Mozilla Public License 2.0'), 'MPL-2.0');
    });

    test('大小写不敏感', () {
      expect(detectLicenseType('mit license'), 'MIT');
      expect(detectLicenseType('MIT LICENSE'), 'MIT');
    });

    test('无法识别的文本与空串返回 null（以详情页全文为准）', () {
      expect(detectLicenseType('some random terms and conditions'), isNull);
      expect(detectLicenseType(''), isNull);
    });
  });
}
