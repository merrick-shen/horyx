import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式存储服务
/// 基于 SharedPreferences 的本地键值存储：
/// 保存用户选择的主题模式（自动/深色/浅色），应用重启后恢复；
/// 读取时对未知值容错（回退到自动模式），避免旧版本或损坏数据导致异常
class ThemeStorage {
  /// 工具类禁止实例化
  ThemeStorage._();

  /// 主题模式的存储键
  static const String _key = 'theme_mode';

  /// 保存主题模式
  static Future<void> save(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  /// 读取主题模式；无记录或值非法时回退到「跟随系统」
  static Future<ThemeMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    return ThemeMode.values.asNameMap()[raw] ?? ThemeMode.system;
  }
}
