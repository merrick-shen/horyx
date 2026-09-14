import 'dart:io';

import 'package:flutter/foundation.dart';

/// 网络工具函数（跨模块共享）
class NetUtils {
  NetUtils._();

  /// 房间码的自定义 scheme：扫码加入房间使用专属 scheme，
  /// 扫到其他 App 的二维码内容时可直接判定非法，给出明确提示
  static const String _joinScheme = 'horyx';

  /// 房间码 Uri 的 host 段（`horyx://join` 中的 join 即 Uri 的 host）
  static const String _joinUriHost = 'join';

  /// 构造扫码加入房间码：`horyx://join?host=<IPv4>&port=<端口>`
  /// 房主等待页据此生成二维码；host 为 localIpv4 取到的局域网地址
  static String buildRoomJoinCode({required String host, required int port}) {
    return Uri(
      scheme: _joinScheme,
      host: _joinUriHost,
      queryParameters: {'host': host, 'port': '$port'},
    ).toString();
  }

  /// 解析扫码得到的房间码；内容非法（scheme 不符 / 缺参 / host 非 IPv4 /
  /// 端口越界 / 百分号编码损坏）返回 null，由调用方提示"这不是本游戏的房间码"
  /// host 仅接受 IPv4：房间码由本 App 生成（localIpv4 只取 IPv4），与
  /// 加入页「IP:端口」手输格式不支持 IPv6 的限制保持一致
  /// 额外参数忽略（宽松）：未来扩展字段不破坏旧版解析
  static ({String host, int port})? parseRoomJoinCode(String raw) {
    final uri = Uri.tryParse(raw.trim());
    // scheme 与 Uri host 解析时归一化为小写，与常量直接比较即可
    if (uri == null || uri.scheme != _joinScheme || uri.host != _joinUriHost) {
      return null;
    }
    try {
      final host = uri.queryParameters['host'];
      final portValue = uri.queryParameters['port'];
      final port = portValue == null ? null : int.tryParse(portValue);
      if (host == null || port == null || !_isValidIpv4(host)) return null;
      if (port < 1 || port > 65535) return null;
      return (host: host, port: port);
    } on FormatException {
      // 百分号编码损坏（如 %zz）时 queryParameters 解码抛出，按非法内容处理
      return null;
    }
  }

  /// IPv4 格式校验：四段 0-255 的数字
  /// 与加入页手输校验同规则；接入扫码入口时可收敛为共用本实现
  static bool _isValidIpv4(String value) {
    final segments = value.split('.');
    if (segments.length != 4) return false;
    for (final segment in segments) {
      if (segment.isEmpty || segment.length > 3) return false;
      final number = int.tryParse(segment);
      if (number == null || number < 0 || number > 255) return false;
    }
    return true;
  }

  /// 获取本机局域网 IPv4 地址；无可用网卡时返回 null
  /// 多网卡（Wi-Fi + 移动数据同时开启）时按网段优先级取最可能是
  /// 局域网的地址：192.168/16 > 172.16/12 > 10/8 > 其他——家庭/办公
  /// 路由器普遍使用 192.168 段，10/8 常见于企业内网与运营商移动数据
  /// （CGNAT），对端无法直连；取错时仅影响展示，好友可手动输入兜底
  static Future<String?> localIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final candidates = [
        for (final interface in interfaces)
          for (final address in interface.addresses)
            if (!address.isLoopback) address.address,
      ];
      if (candidates.isEmpty) return null;
      // 稳定排序保持同优先级下的网卡枚举顺序（取错场景的兜底语义不变）
      candidates.sort((a, b) => _lanPriority(a).compareTo(_lanPriority(b)));
      return candidates.first;
    } catch (e) {
      // 列举网卡失败按无地址处理（调用方均有兜底路径），留痕便于排查
      debugPrint('NetUtils 枚举网卡失败: $e');
    }
    return null;
  }

  /// 地址的局域网优先级（越小越优先）：192.168/16 < 172.16/12 < 10/8 < 其他
  /// 移动数据的运营商 CGNAT 地址多为 10/8 段（如 10.3.106.202），排最后
  static int _lanPriority(String address) {
    final octets = address.split('.');
    final first = octets.length == 4 ? int.tryParse(octets[0]) : null;
    final second = octets.length == 4 ? int.tryParse(octets[1]) : null;
    if (first == null || second == null) return 3;
    if (first == 192 && second == 168) return 0;
    if (first == 172 && second >= 16 && second <= 31) return 1;
    if (first == 10) return 2;
    return 3;
  }
}
