import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// 各游戏存档模型的基础契约：存档管理页展示（摘要/保存时间）所需的最小接口
/// （GameInfo.archive 适配经此免转型读取展示数据）
abstract interface class GameArchiveSummary {
  /// 存档进度摘要：与各游戏设置页「继续上次对局」卡片文案同源，
  /// 单点维护于各存档模型
  String get summary;

  /// 存档时间
  DateTime get savedAt;
}

/// 多存档索引条目：单条存档的展示元数据（id、归属游戏、摘要、保存时间）。
/// 索引键集中缓存这些字段，存档管理页列出全部存档时无需逐条解析数据键
class ArchiveIndexEntry {
  const ArchiveIndexEntry({
    required this.id,
    required this.gameId,
    required this.summary,
    required this.savedAt,
  });

  /// 存档唯一标识（全局唯一，微秒时间戳 + 随机后缀）
  final String id;

  /// 归属游戏标识（与 GameRegistry 登记名一致）
  final String gameId;

  /// 进度摘要（保存时取自存档模型，展示用冗余副本）
  final String summary;

  /// 存档时间（保存时取自存档模型，展示用冗余副本）
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'gameId': gameId,
        'summary': summary,
        'savedAt': savedAt.toIso8601String(),
      };

  /// 反序列化；字段缺失或类型不符时抛出异常，由索引读取侧按条跳过
  factory ArchiveIndexEntry.fromJson(Map<String, dynamic> json) {
    return ArchiveIndexEntry(
      id: json['id'] as String,
      gameId: json['gameId'] as String,
      summary: json['summary'] as String,
      savedAt: DateTime.parse(json['savedAt'] as String),
    );
  }
}

/// 多存档记录：单条存档的完整内容（标识 + 游戏状态）
class ArchiveRecord<T> {
  const ArchiveRecord({required this.id, required this.state});

  final String id;

  final T state;
}

/// 对局存档服务泛型基类（多存档仓库）
/// 基于 SharedPreferences 的本地 JSON 存储，采用「索引键 + 数据键」结构：
/// - 索引键（archive_index_v2）集中存放全部存档的展示元数据；
/// - 每条存档一个数据键（`archive_data_<id>`），完整状态序列化后单键写入
///   （单键写入具备原子性）。
/// 一致性约定：保存先写数据键再更新索引，删除先删数据键再移除索引——
/// 两键写入非原子，崩溃窗口最多留下索引不可见的孤儿数据键或悬空索引条目，
/// 均无害：悬空条目由恢复路径懒清理，孤儿数据键等待覆盖或删除。
/// 读取容错：索引整体损坏视为空索引、单条损坏按条跳过、数据键解析失败
/// 视为无此档；单条存档损坏不影响其余存档。
///
/// 各游戏子类只需声明 gameId、存储键与模型双向序列化（见各 *_storage.dart）。
/// 旧单存档 save/load/clear 三件套为过渡期兼容 API（现状调用方尚未迁移，
/// 行为不变），各游戏页接入多存档 API 后移除
abstract class ArchiveStorage<T extends GameArchiveSummary> {
  const ArchiveStorage();

  /// 多存档全局索引键（全部游戏共用）
  static const _indexKey = 'archive_index_v2';

  /// 数据键前缀（完整键为 archive_data_<存档id>）
  static const _dataKeyPrefix = 'archive_data_';

  static final Random _random = Random();

  /// 旧单存档的存储键（各游戏唯一；后续阶段转为迁移源 legacyKey）
  String get storageKey;

  /// 多存档归属游戏标识（与 GameRegistry 登记名一致）
  String get gameId;

  /// 模型反序列化（各游戏模型类型不同）
  T fromJson(Map<String, dynamic> json);

  /// 模型序列化（Dart 泛型无法约束结构化类型，故由子类转发 toJson）
  Map<String, dynamic> toJson(T state);

  // ---------------------------------------------------------------------------
  // 旧单存档 API（现状行为保留）
  // ---------------------------------------------------------------------------

  /// 保存对局状态（单存档语义：固定键覆盖写）
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

  // ---------------------------------------------------------------------------
  // 多存档 API
  // ---------------------------------------------------------------------------

  /// 保存一条存档：[id] 为空时新建并生成标识；传入已有 id 则覆盖更新该条
  /// （索引中的摘要与保存时间同步刷新）。返回存档 id
  Future<String> saveArchive(T state, {String? id}) async {
    final archiveId = id ?? _generateId();
    final prefs = await SharedPreferences.getInstance();
    // 先写数据键再更新索引（一致性约定见类注释）
    await prefs.setString(
      '$_dataKeyPrefix$archiveId',
      jsonEncode({'gameId': gameId, 'state': toJson(state)}),
    );
    final entries = await _loadIndex(prefs);
    final entry = ArchiveIndexEntry(
      id: archiveId,
      gameId: gameId,
      summary: state.summary,
      savedAt: state.savedAt,
    );
    await _writeIndex(
      prefs,
      [...entries.where((e) => e.id != archiveId), entry],
    );
    return archiveId;
  }

  /// 读取该游戏最新一条存档（按保存时间倒序取首个可加载条目）；
  /// 无存档返回 null。数据键缺失/损坏的条目会被懒清理并继续尝试更早存档
  Future<ArchiveRecord<T>?> loadLatest() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = (await _loadIndex(prefs))
        .where((e) => e.gameId == gameId)
        .toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    for (final entry in entries) {
      final record = await _loadRecord(prefs, entry.id);
      if (record != null) return record;
      await _pruneArchive(prefs, entry.id);
    }
    return null;
  }

  /// 读取指定 id 的存档；不存在、归属不符或损坏时返回 null
  Future<ArchiveRecord<T>?> loadById(String id) async {
    final prefs = await SharedPreferences.getInstance();
    return _loadRecord(prefs, id);
  }

  /// 列出该游戏的全部存档条目（按保存时间倒序）
  Future<List<ArchiveIndexEntry>> loadSummaries() async {
    final prefs = await SharedPreferences.getInstance();
    final entries =
        (await _loadIndex(prefs)).where((e) => e.gameId == gameId).toList()
          ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return entries;
  }

  /// 列出全部游戏的存档条目（按保存时间倒序；存档管理页平铺展示用）
  static Future<List<ArchiveIndexEntry>> loadAllSummaries() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await _loadIndex(prefs)
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return entries;
  }

  /// 删除指定 id 的存档（数据键与索引条目一并清除；id 不存在时无副作用）
  Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await _pruneArchive(prefs, id);
  }

  // ---------------------------------------------------------------------------
  // 内部实现
  // ---------------------------------------------------------------------------

  /// 读取并解析数据键；id 归属不符、数据缺失或损坏时返回 null
  Future<ArchiveRecord<T>?> _loadRecord(SharedPreferences prefs, String id) async {
    try {
      final raw = prefs.getString('$_dataKeyPrefix$id');
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['gameId'] != gameId) return null;
      final state = fromJson(json['state'] as Map<String, dynamic>);
      return ArchiveRecord(id: id, state: state);
    } catch (_) {
      return null;
    }
  }

  /// 清除一条存档：先删数据键再移除索引（一致性约定见类注释）
  Future<void> _pruneArchive(SharedPreferences prefs, String id) async {
    await prefs.remove('$_dataKeyPrefix$id');
    final entries = await _loadIndex(prefs);
    await _writeIndex(prefs, [for (final e in entries) if (e.id != id) e]);
  }

  /// 读取索引：整体损坏视为空索引，单条损坏按条跳过
  static Future<List<ArchiveIndexEntry>> _loadIndex(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_indexKey);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      final entries = <ArchiveIndexEntry>[];
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        try {
          entries.add(ArchiveIndexEntry.fromJson(item));
        } catch (_) {
          // 单条元数据损坏：跳过该条，不影响其余条目
        }
      }
      return entries;
    } catch (_) {
      // 索引整体损坏：视为空索引（数据键留存，等待覆盖或懒清理）
      return const [];
    }
  }

  static Future<void> _writeIndex(
    SharedPreferences prefs,
    List<ArchiveIndexEntry> entries,
  ) async {
    await prefs.setString(
      _indexKey,
      jsonEncode([for (final e in entries) e.toJson()]),
    );
  }

  /// 存档 id：微秒时间戳 + 随机后缀，用户触发频率下可视为全局唯一
  static String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(900) + 100}';
}
