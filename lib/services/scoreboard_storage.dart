import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/scoreboard_game_state.dart';

/// 计分器存档服务
/// 基于 SharedPreferences 的本地 JSON 存储：
/// 完整状态先序列化为一个字符串再单键写入（单键写入具备原子性），
/// 读取时对损坏数据容错（解析失败视为无存档），避免半写状态影响进入流程
class ScoreboardStorage {
  /// 工具类禁止实例化
  ScoreboardStorage._();

  /// 未完成计分的存储键
  static const String _key = 'scoreboard_unfinished_state';

  /// 保存计分状态
  static Future<void> save(ScoreboardGameState state) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(state.toJson());
    await prefs.setString(_key, json);
  }

  /// 读取未完成计分；无存档或存档损坏时返回 null
  static Future<ScoreboardGameState?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      return ScoreboardGameState.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      // JSON 损坏、字段缺失等异常均视为无可用存档
      return null;
    }
  }

  /// 清除存档
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
