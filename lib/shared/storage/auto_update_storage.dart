import 'package:shared_preferences/shared_preferences.dart';

/// 「自动检查更新」开关存储
/// 用户在设置中控制启动时的自动检查行为；未设置时视为开启（默认开启）
class AutoUpdateStorage {
  /// 工具类禁止实例化
  AutoUpdateStorage._();

  /// 自动检查更新开关的存储键
  static const String _key = 'update_auto_check_enabled';

  /// 读取开关状态（未设置默认开启）
  static Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  /// 保存开关状态
  static Future<void> save(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}
