import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/shared/update/version_comparator.dart';

/// VersionComparator 版本比较测试（更新检测）
void main() {
  group('compare', () {
    test('tag 带 v 前缀时可比较', () {
      expect(VersionComparator.compare('v0.10.0', '0.9.0'), VersionRelation.newer);
      expect(VersionComparator.compare('v0.9.0', '0.9.0'), VersionRelation.same);
    });

    test('tag 不带 v 前缀时也可比较', () {
      expect(VersionComparator.compare('0.9.1', '0.9.0'), VersionRelation.newer);
      expect(VersionComparator.compare('0.9.0', '0.9.0'), VersionRelation.same);
    });

    test('release 更旧（本地领先）判 older', () {
      expect(VersionComparator.compare('0.8.0', '0.9.0'), VersionRelation.older);
    });

    test('逐段比较：主/次/补丁号各自生效', () {
      expect(VersionComparator.compare('1.0.0', '0.9.9'), VersionRelation.newer);
      expect(VersionComparator.compare('0.10.0', '0.9.9'), VersionRelation.newer);
      expect(VersionComparator.compare('0.9.10', '0.9.9'), VersionRelation.newer);
      // 逐段数值比较而非字符串比较：10 > 9
      expect(VersionComparator.compare('0.10.0', '0.9.0'), VersionRelation.newer);
    });

    test('缺段补 0：1.0 与 1.0.0 等价', () {
      expect(VersionComparator.compare('1.0', '1.0.0'), VersionRelation.same);
      expect(VersionComparator.compare('1.1', '1.0.0'), VersionRelation.newer);
    });

    test('段数超出时仍可比较', () {
      expect(VersionComparator.compare('0.9.0.1', '0.9.0'), VersionRelation.newer);
      expect(VersionComparator.compare('0.9.0', '0.9.0.1'), VersionRelation.older);
    });

    test('tag 携带 +build 后缀时忽略', () {
      expect(VersionComparator.compare('v0.10.0+9', '0.9.0'), VersionRelation.newer);
      expect(VersionComparator.compare('v0.9.0+9', '0.9.0'), VersionRelation.same);
    });

    test('任一版本格式非法判 invalid', () {
      expect(VersionComparator.compare('abc', '0.9.0'), VersionRelation.invalid);
      expect(VersionComparator.compare('v0.9.x', '0.9.0'), VersionRelation.invalid);
      expect(VersionComparator.compare('', '0.9.0'), VersionRelation.invalid);
      expect(VersionComparator.compare('v0.9.0', ''), VersionRelation.invalid);
    });

    test('tag 首尾空白容忍', () {
      expect(VersionComparator.compare(' v0.9.1 ', '0.9.0'), VersionRelation.newer);
    });
  });
}
