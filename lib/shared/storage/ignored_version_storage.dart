import 'package:shared_preferences/shared_preferences.dart';

/// 更新「忽略此版本」存储
/// 记录用户在自动检查更新弹窗中明确忽略的版本（release tag），
/// 自动检查命中已忽略版本时静默跳过弹窗，避免每次启动重复打扰；
/// 手动检查更新不受影响，仍会正常弹窗
class IgnoredVersionStorage {
  /// 工具类禁止实例化
  IgnoredVersionStorage._();

  /// 忽略版本的存储键
  static const String _key = 'update_ignored_version';

  /// 记录被忽略的版本（release tag，如 v1.2.0；新忽略覆盖旧记录）
  static Future<void> save(String tagName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, tagName);
  }

  /// 指定版本是否已被用户忽略
  static Future<bool> isIgnored(String tagName) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) == tagName;
  }
}
