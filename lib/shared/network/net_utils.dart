import 'dart:io';

import 'package:flutter/foundation.dart';

/// 网络工具函数（跨模块共享）
class NetUtils {
  NetUtils._();

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
