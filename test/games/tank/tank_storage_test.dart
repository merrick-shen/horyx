import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:horyx/games/tank/models/tank_game_state.dart';
import 'package:horyx/games/tank/pages/tank_page.dart';
import 'package:horyx/games/tank/services/tank_storage.dart';

void main() {
  setUp(() {
    // 每个测试使用独立的模拟存储，避免相互污染
    SharedPreferences.setMockInitialValues({});
  });

  group('TankGameState 序列化', () {
    test('JSON 往返序列化数据一致', () {
      final state = TankGameState(
        redScore: 3,
        greenScore: 5,
        savedAt: DateTime(2026, 8, 31, 12, 30),
      );

      final restored = TankGameState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
      );

      expect(restored.redScore, 3);
      expect(restored.greenScore, 5);
      expect(restored.savedAt, state.savedAt);
    });

    test('字段缺失时抛出类型错误', () {
      // fromJson 直接强转字段，缺字段抛 TypeError；
      // 存档层 load 对任意异常统一容错视为无存档
      expect(
        () => TankGameState.fromJson({'redScore': 1}),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('TankStorage 存档服务', () {
    test('无存档时 load 返回 null', () async {
      expect(await TankStorage.instance.load(), isNull);
    });

    test('save 后 load 可完整还原', () async {
      await TankStorage.instance.save(
        TankGameState(
          redScore: 2,
          greenScore: 4,
          savedAt: DateTime(2026, 8, 31),
        ),
      );

      final loaded = await TankStorage.instance.load();
      expect(loaded, isNotNull);
      expect(loaded!.redScore, 2);
      expect(loaded.greenScore, 4);
    });

    test('存档数据损坏时 load 容错返回 null', () async {
      final prefs = await SharedPreferences.getInstance();
      // 模拟半写/损坏数据
      await prefs.setString('tank_unfinished_state', '{broken json');
      expect(await TankStorage.instance.load(), isNull);
    });

    test('clear 后存档清空', () async {
      await TankStorage.instance.save(
        TankGameState(
          redScore: 1,
          greenScore: 1,
          savedAt: DateTime(2026, 8, 31),
        ),
      );
      await TankStorage.instance.clear();
      expect(await TankStorage.instance.load(), isNull);
    });
  });

  group('TankStorage 多存档 API', () {
    TankGameState sampleState() {
      return TankGameState(
        redScore: 3,
        greenScore: 5,
        savedAt: DateTime(2026, 8, 31, 12, 30),
      );
    }

    test('gameId 与注册表登记名一致', () {
      expect(TankStorage.instance.gameId, TankPage.gameName);
    });

    test('saveArchive 新建后 loadLatest/loadById 可完整还原', () async {
      final state = sampleState();
      final id = await TankStorage.instance.saveArchive(state);

      final latest = await TankStorage.instance.loadLatest();
      expect(latest, isNotNull);
      expect(latest!.id, id);
      expect(latest.state.redScore, 3);
      expect(latest.state.greenScore, 5);

      final byId = await TankStorage.instance.loadById(id);
      expect(byId!.state.savedAt, state.savedAt);
      expect(byId.state.summary, state.summary);
    });

    test('传入已有 id 覆盖：条目数不变、进度刷新', () async {
      final id = await TankStorage.instance.saveArchive(sampleState());
      final updated = TankGameState(
        redScore: 7,
        greenScore: 6,
        savedAt: DateTime(2026, 8, 31, 18),
      );
      await TankStorage.instance.saveArchive(updated, id: id);

      final summaries = await TankStorage.instance.loadSummaries();
      expect(summaries, hasLength(1));
      expect(summaries.single.id, id);
      final record = await TankStorage.instance.loadById(id);
      expect(record!.state.redScore, 7);
      expect(record.state.greenScore, 6);
    });

    test('remove 后恢复入口数据清空', () async {
      final id = await TankStorage.instance.saveArchive(sampleState());
      await TankStorage.instance.remove(id);
      expect(await TankStorage.instance.loadLatest(), isNull);
      expect(await TankStorage.instance.loadSummaries(), isEmpty);
    });
  });
}
