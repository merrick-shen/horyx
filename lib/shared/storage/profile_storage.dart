import 'package:shared_preferences/shared_preferences.dart';

/// 用户名存储服务
/// 基于 SharedPreferences 的本地键值存储：
/// 保存用户设置的名字，应用重启后恢复；未设置状态用 null 表达
class ProfileStorage {
  /// 工具类禁止实例化
  ProfileStorage._();

  /// 用户名的存储键
  static const String _key = 'user_name';

  /// 保存名字（调用方保证已 trim、非空、≤12 字素）
  static Future<void> save(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, name);
  }

  /// 读取名字；无记录或空串返回 null（未设置）
  static Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    return raw == null || raw.isEmpty ? null : raw;
  }
}
