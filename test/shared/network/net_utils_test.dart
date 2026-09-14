import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/shared/network/net_utils.dart';

/// NetUtils 房间码编解码测试（扫码加入房间）
void main() {
  group('buildRoomJoinCode', () {
    test('构造标准房间码格式', () {
      expect(
        NetUtils.buildRoomJoinCode(host: '192.168.124.3', port: 45654),
        'horyx://join?host=192.168.124.3&port=45654',
      );
    });

    test('构造后可无损解析', () {
      final code = NetUtils.buildRoomJoinCode(host: '10.0.0.255', port: 1);
      expect(NetUtils.parseRoomJoinCode(code), (host: '10.0.0.255', port: 1));
    });
  });

  group('parseRoomJoinCode', () {
    test('标准房间码解析成功', () {
      expect(
        NetUtils.parseRoomJoinCode(
          'horyx://join?host=192.168.1.100&port=45654',
        ),
        (host: '192.168.1.100', port: 45654),
      );
    });

    test('scheme 与 Uri host 大写时归一化为小写，仍可解析', () {
      expect(
        NetUtils.parseRoomJoinCode(
          'HORYX://JOIN?host=192.168.1.100&port=45654',
        ),
        (host: '192.168.1.100', port: 45654),
      );
    });

    test('额外参数忽略（未来扩展兼容）', () {
      expect(
        NetUtils.parseRoomJoinCode(
          'horyx://join?host=192.168.1.100&port=45654&v=2',
        ),
        (host: '192.168.1.100', port: 45654),
      );
    });

    test('端口边界值 1 与 65535 合法', () {
      expect(
        NetUtils.parseRoomJoinCode('horyx://join?host=1.2.3.4&port=1'),
        (host: '1.2.3.4', port: 1),
      );
      expect(
        NetUtils.parseRoomJoinCode('horyx://join?host=1.2.3.4&port=65535'),
        (host: '1.2.3.4', port: 65535),
      );
    });

    test('首尾空白容忍（扫描内容可能带换行）', () {
      expect(
        NetUtils.parseRoomJoinCode(
          '  horyx://join?host=1.2.3.4&port=45654\n',
        ),
        (host: '1.2.3.4', port: 45654),
      );
    });

    test('非本游戏 scheme 返回 null', () {
      expect(
        NetUtils.parseRoomJoinCode('https://join?host=1.2.3.4&port=45654'),
        isNull,
      );
      expect(
        NetUtils.parseRoomJoinCode('weixin://join?host=1.2.3.4&port=45654'),
        isNull,
      );
    });

    test('Uri host 段不是 join 返回 null', () {
      expect(
        NetUtils.parseRoomJoinCode('horyx://other?host=1.2.3.4&port=1'),
        isNull,
      );
    });

    test('缺 host 或缺 port 返回 null', () {
      expect(
        NetUtils.parseRoomJoinCode('horyx://join?port=45654'),
        isNull,
      );
      expect(
        NetUtils.parseRoomJoinCode('horyx://join?host=1.2.3.4'),
        isNull,
      );
      expect(NetUtils.parseRoomJoinCode('horyx://join'), isNull);
    });

    test('host 非 IPv4 返回 null', () {
      expect(
        NetUtils.parseRoomJoinCode(
          'horyx://join?host=999.1.1.1&port=45654',
        ),
        isNull,
      );
      expect(
        NetUtils.parseRoomJoinCode('horyx://join?host=abc&port=45654'),
        isNull,
      );
      expect(
        NetUtils.parseRoomJoinCode('horyx://join?host=1.2.3&port=45654'),
        isNull,
      );
    });

    test('端口越界或非数字返回 null', () {
      expect(
        NetUtils.parseRoomJoinCode('horyx://join?host=1.2.3.4&port=0'),
        isNull,
      );
      expect(
        NetUtils.parseRoomJoinCode('horyx://join?host=1.2.3.4&port=65536'),
        isNull,
      );
      expect(
        NetUtils.parseRoomJoinCode('horyx://join?host=1.2.3.4&port=abc'),
        isNull,
      );
    });

    test('无关文本与空串返回 null', () {
      expect(NetUtils.parseRoomJoinCode('hello world'), isNull);
      expect(NetUtils.parseRoomJoinCode(''), isNull);
    });

    test('百分号编码损坏不抛异常，返回 null', () {
      expect(
        NetUtils.parseRoomJoinCode('horyx://join?host=%zz&port=45654'),
        isNull,
      );
    });
  });
}
