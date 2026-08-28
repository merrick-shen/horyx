import 'dart:io';

import 'package:flutter/foundation.dart';

/// 网络工具函数（跨模块共享）
class NetUtils {
  NetUtils._();

  /// 获取本机局域网 IPv4 地址；无可用网卡时返回 null
  /// 取第一个非回环地址——多网卡（VPN/双 Wi-Fi）场景可能取错，
  /// 调用方（房主等待页地址展示）取错时仅影响展示，好友可手动查询兜底
  static Future<String?> localIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) return address.address;
        }
      }
    } catch (e) {
      // 列举网卡失败按无地址处理（调用方均有兜底路径），留痕便于排查
      debugPrint('NetUtils 枚举网卡失败: $e');
    }
    return null;
  }
}
