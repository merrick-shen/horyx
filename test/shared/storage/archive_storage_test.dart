import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:horyx/shared/storage/archive_storage.dart';

/// 测试用存档状态（实现展示契约）
class _FakeState implements GameArchiveSummary {
  const _FakeState(this.summary, this.savedAt);

  @override
  final String summary;

  @override
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'savedAt': savedAt.toIso8601String(),
      };

  static _FakeState fromJson(Map<String, dynamic> json) => _FakeState(
        json['summary'] as String,
        DateTime.parse(json['savedAt'] as String),
      );
}

class _TestStorage extends ArchiveStorage<_FakeState> {
  const _TestStorage();

  @override
  String get gameId => '测试游戏';

  @override
  _FakeState fromJson(Map<String, dynamic> json) => _FakeState.fromJson(json);

  @override
  Map<String, dynamic> toJson(_FakeState state) => state.toJson();
}

/// 第二个游戏存储：验证索引按 gameId 隔离
class _OtherStorage extends ArchiveStorage<_FakeState> {
  const _OtherStorage();

  @override
  String get gameId => '另一游戏';

  @override
  _FakeState fromJson(Map<String, dynamic> json) => _FakeState.fromJson(json);

  @override
  Map<String, dynamic> toJson(_FakeState state) => state.toJson();
}

void main() {
  const storage = _TestStorage();
  const otherStorage = _OtherStorage();

  const indexKey = 'archive_index_v2';
  String dataKey(String id) => 'archive_data_$id';

  setUp(() {
    // 每个测试使用独立的模拟存储，避免相互污染
    SharedPreferences.setMockInitialValues({});
  });

  _FakeState stateAt(DateTime time, [String summary = '进度摘要']) =>
      _FakeState(summary, time);

  group('saveArchive 新建与覆盖', () {
    test('新建：返回 id 并写入数据键与索引条目', () async {
      final savedAt = DateTime(2026, 9, 28, 12, 30);
      final id = await storage.saveArchive(stateAt(savedAt));

      expect(id, isNotEmpty);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(dataKey(id));
      expect(raw, isNotNull);
      final data = jsonDecode(raw!) as Map<String, dynamic>;
      expect(data['gameId'], '测试游戏');
      expect(data['state'], isA<Map<String, dynamic>>());

      final record = await storage.loadById(id);
      expect(record, isNotNull);
      expect(record!.id, id);
      expect(record.state.summary, '进度摘要');
      expect(record.state.savedAt, savedAt);
    });

    test('多次新建：id 互不相同，条目数随之增加', () async {
      final id1 = await storage.saveArchive(stateAt(DateTime(2026, 9, 28, 10)));
      final id2 = await storage.saveArchive(stateAt(DateTime(2026, 9, 28, 11)));
      expect(id1, isNot(id2));

      final summaries = await storage.loadSummaries();
      expect(summaries, hasLength(2));
      expect(summaries.map((e) => e.id), containsAll([id1, id2]));
    });

    test('传入已有 id 覆盖：条目数不变，摘要与保存时间刷新', () async {
      final id = await storage.saveArchive(stateAt(DateTime(2026, 9, 28, 10)));
      final newSavedAt = DateTime(2026, 9, 28, 15);
      await storage.saveArchive(
        stateAt(newSavedAt, '推进后进度'),
        id: id,
      );

      final summaries = await storage.loadSummaries();
      expect(summaries, hasLength(1));
      expect(summaries.single.id, id);
      expect(summaries.single.summary, '推进后进度');
      expect(summaries.single.savedAt, newSavedAt);

      final record = await storage.loadById(id);
      expect(record!.state.summary, '推进后进度');
      expect(record.state.savedAt, newSavedAt);
    });
  });

  group('loadLatest / loadById', () {
    test('无存档时返回 null', () async {
      expect(await storage.loadLatest(), isNull);
    });

    test('多条存档时返回保存时间最新的一条', () async {
      await storage.saveArchive(stateAt(DateTime(2026, 9, 28, 10), '旧档'));
      await storage.saveArchive(stateAt(DateTime(2026, 9, 28, 18), '新档'));

      final latest = await storage.loadLatest();
      expect(latest, isNotNull);
      expect(latest!.state.summary, '新档');
    });

    test('loadById 未命中返回 null', () async {
      expect(await storage.loadById('not-exist'), isNull);
    });
  });

  group('gameId 隔离', () {
    test('各游戏 loadSummaries 只见自己的存档', () async {
      await storage.saveArchive(stateAt(DateTime(2026, 9, 28, 10)));
      await otherStorage.saveArchive(stateAt(DateTime(2026, 9, 28, 11)));

      expect(await storage.loadSummaries(), hasLength(1));
      expect((await storage.loadSummaries()).single.gameId, '测试游戏');
      expect(await otherStorage.loadSummaries(), hasLength(1));
      expect((await otherStorage.loadSummaries()).single.gameId, '另一游戏');
    });

    test('loadAllSummaries 汇总全部游戏并倒序', () async {
      await storage.saveArchive(stateAt(DateTime(2026, 9, 28, 10), 'A1'));
      await otherStorage.saveArchive(stateAt(DateTime(2026, 9, 28, 12), 'B1'));
      await storage.saveArchive(stateAt(DateTime(2026, 9, 28, 11), 'A2'));

      final all = await ArchiveStorage.loadAllSummaries();
      expect(all, hasLength(3));
      // 倒序：时间最新的在最前
      expect(all.map((e) => e.summary).toList(), ['B1', 'A2', 'A1']);
    });

    test('loadLatest 不受其他游戏存档影响', () async {
      await otherStorage.saveArchive(stateAt(DateTime(2026, 9, 28, 20), '别家新档'));
      await storage.saveArchive(stateAt(DateTime(2026, 9, 28, 10), '自家档'));

      expect((await storage.loadLatest())!.state.summary, '自家档');
    });
  });

  group('remove', () {
    test('删除后数据键与索引条目一并清除', () async {
      final id = await storage.saveArchive(stateAt(DateTime(2026, 9, 28)));
      await storage.remove(id);

      expect(await storage.loadById(id), isNull);
      expect(await storage.loadSummaries(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(dataKey(id)), isNull);
    });

    test('删除单条不影响其余存档', () async {
      final id1 = await storage.saveArchive(stateAt(DateTime(2026, 9, 28, 10)));
      final id2 = await storage.saveArchive(stateAt(DateTime(2026, 9, 28, 11)));
      await storage.remove(id1);

      final summaries = await storage.loadSummaries();
      expect(summaries, hasLength(1));
      expect(summaries.single.id, id2);
    });

    test('删除不存在的 id 无副作用', () async {
      await storage.remove('not-exist');
      expect(await storage.loadSummaries(), isEmpty);
    });
  });

  group('容错', () {
    test('索引整体损坏视为空索引', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(indexKey, '{broken json');

      expect(await storage.loadSummaries(), isEmpty);
      expect(await storage.loadLatest(), isNull);

      // 损坏索引被后续保存正常重建
      await storage.saveArchive(stateAt(DateTime(2026, 9, 28)));
      expect(await storage.loadSummaries(), hasLength(1));
    });

    test('索引中单条元数据损坏时跳过坏条', () async {
      final id = await storage.saveArchive(stateAt(DateTime(2026, 9, 28)));
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(indexKey)!;
      final broken = jsonDecode(raw) as List;
      broken.add({'id': 'bad'});
      await prefs.setString(indexKey, jsonEncode(broken));

      final summaries = await storage.loadSummaries();
      expect(summaries, hasLength(1));
      expect(summaries.single.id, id);
    });

    test('最新档数据键损坏：loadLatest 懒清理后返回更早存档', () async {
      final oldId = await storage.saveArchive(stateAt(DateTime(2026, 9, 28, 10), '旧档'));
      final newId = await storage.saveArchive(stateAt(DateTime(2026, 9, 28, 18), '新档'));

      // 手动损坏最新档数据键
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(dataKey(newId), '{broken json');

      final latest = await storage.loadLatest();
      expect(latest, isNotNull);
      expect(latest!.state.summary, '旧档');

      // 损坏条目已被清理，仅剩旧档
      final summaries = await storage.loadSummaries();
      expect(summaries, hasLength(1));
      expect(summaries.single.id, oldId);
    });

    test('索引悬空条目（数据键缺失）：loadLatest 懒清理', () async {
      await storage.saveArchive(stateAt(DateTime(2026, 9, 28, 10)));
      final prefs = await SharedPreferences.getInstance();
      // 追加一条指向不存在数据键的索引条目（时间更新，排最前）
      final raw = prefs.getString(indexKey)!;
      final list = jsonDecode(raw) as List;
      list.add({
        'id': 'ghost-id',
        'gameId': '测试游戏',
        'summary': '幽灵条目',
        'savedAt': DateTime(2026, 9, 28, 20).toIso8601String(),
      });
      await prefs.setString(indexKey, jsonEncode(list));

      final latest = await storage.loadLatest();
      expect(latest, isNotNull);
      expect(latest!.state.summary, '进度摘要');

      final summaries = await storage.loadSummaries();
      expect(summaries, hasLength(1));
      expect(summaries.single.id, isNot('ghost-id'));
    });

    test('数据键归属不符时 loadById 返回 null', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        dataKey('cross-id'),
        jsonEncode({
          'gameId': '另一游戏',
          'state': stateAt(DateTime(2026, 9, 28)).toJson(),
        }),
      );

      expect(await storage.loadById('cross-id'), isNull);
    });
  });
}
