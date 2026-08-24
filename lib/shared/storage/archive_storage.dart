import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 对局存档服务泛型基类
/// 基于 SharedPreferences 的本地 JSON 存储：
/// 完整状态先序列化为一个字符串再单键写入（单键写入具备原子性），
/// 读取时对损坏数据容错（解析失败视为无存档），避免半写状态影响进入流程。
/// 各游戏子类只需声明存储键与模型双向序列化（见各 *_storage.dart），
/// 新增游戏存档不必再复制 save/load/clear 三件套
abstract class ArchiveStorage<T> {
  const ArchiveStorage();

  /// 未完成对局的存储键（各游戏唯一）
  String get storageKey;

  /// 模型反序列化（各游戏模型类型不同）
  T fromJson(Map<String, dynamic> json);

  /// 模型序列化（Dart 泛型无法约束结构化类型，故由子类转发 toJson）
  Map<String, dynamic> toJson(T state);

  /// 保存对局状态
  Future<void> save(T state) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(toJson(state));
    await prefs.setString(storageKey, json);
  }

  /// 读取未完成对局；无存档或存档损坏时返回 null
  Future<T?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null) return null;
      return fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // JSON 损坏、字段缺失等异常均视为无可用存档
      return null;
    }
  }

  /// 清除存档
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }
}
