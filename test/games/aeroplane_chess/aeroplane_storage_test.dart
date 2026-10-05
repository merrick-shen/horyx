import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';
import 'package:horyx/games/aeroplane_chess/pages/aeroplane_page.dart';
import 'package:horyx/games/aeroplane_chess/services/aeroplane_storage.dart';

void main() {
  setUp(() {
    // 每个测试使用独立的模拟存储，避免相互污染
    SharedPreferences.setMockInitialValues({});
  });

  /// 构造一个进行中的对局状态（绿机在环、红机入跑道、有连 6 与移动记录）
  AeroplaneGameState sampleState() => AeroplaneGameState(
        players: const [
          AeroplanePlayer(color: AeroplaneColor.green, name: '玩家1'),
          AeroplanePlayer(color: AeroplaneColor.red, name: '玩家2'),
        ],
        planes: {
          AeroplaneColor.green: [
            PlanePosition(zone: PlaneZone.ring, index: 43),
            PlanePosition(zone: PlaneZone.goal, index: 0),
            PlanePosition(zone: PlaneZone.hangar, index: 2),
            PlanePosition(zone: PlaneZone.hangar, index: 3),
          ],
          AeroplaneColor.red: [
            PlanePosition(zone: PlaneZone.runway, index: 1),
            PlanePosition(zone: PlaneZone.hangar, index: 1),
            PlanePosition(zone: PlaneZone.hangar, index: 2),
            PlanePosition(zone: PlaneZone.hangar, index: 3),
          ],
        },
        currentPlayer: AeroplaneColor.red,
        consecutiveSixes: 1,
        lastMoved: (AeroplaneColor.green, 0),
        gameOver: false,
        winner: null,
        savedAt: DateTime(2026, 10, 1, 12, 30),
      );

  group('AeroplaneStorage 多存档 API', () {
    test('gameId 与注册表登记名一致', () {
      expect(AeroplaneStorage.instance.gameId, AeroplanePage.gameName);
    });

    test('saveArchive 新建后 loadLatest/loadById 可完整还原', () async {
      final state = sampleState();
      final id = await AeroplaneStorage.instance.saveArchive(state);

      final latest = await AeroplaneStorage.instance.loadLatest();
      expect(latest, isNotNull);
      expect(latest!.id, id);
      expect(latest.state.planes, state.planes);
      expect(latest.state.currentPlayer, AeroplaneColor.red);
      expect(latest.state.consecutiveSixes, 1);
      expect(latest.state.lastMoved, (AeroplaneColor.green, 0));
      expect(latest.state.savedAt, state.savedAt);

      final byId = await AeroplaneStorage.instance.loadById(id);
      expect(byId!.state.savedAt, state.savedAt);
      expect(byId.state.savedAt, state.savedAt);
    });

    test('传入已有 id 覆盖：条目数不变、进度刷新', () async {
      final id = await AeroplaneStorage.instance.saveArchive(sampleState());
      final updated = AeroplaneGameState(
        players: const [
          AeroplanePlayer(color: AeroplaneColor.green, name: '玩家1'),
          AeroplanePlayer(color: AeroplaneColor.red, name: '玩家2'),
        ],
        planes: {
          for (final color in AeroplaneColor.values.take(2))
            color: [
              for (var i = 0; i < 4; i++)
                PlanePosition(zone: PlaneZone.hangar, index: i),
            ],
        },
        currentPlayer: AeroplaneColor.green,
        consecutiveSixes: 0,
        gameOver: false,
        winner: null,
        savedAt: DateTime(2026, 10, 1, 20),
      );
      await AeroplaneStorage.instance.saveArchive(updated, id: id);

      final summaries = await AeroplaneStorage.instance.loadSummaries();
      expect(summaries, hasLength(1));
      expect(summaries.single.id, id);
      final record = await AeroplaneStorage.instance.loadById(id);
      expect(record!.state.consecutiveSixes, 0);
      expect(record.state.currentPlayer, AeroplaneColor.green);
      expect(record.state.savedAt, updated.savedAt);
    });

    test('remove 后恢复入口数据清空', () async {
      final id = await AeroplaneStorage.instance.saveArchive(sampleState());
      await AeroplaneStorage.instance.remove(id);
      expect(await AeroplaneStorage.instance.loadLatest(), isNull);
      expect(await AeroplaneStorage.instance.loadSummaries(), isEmpty);
    });

    test('数据键损坏的存档容错为无此档', () async {
      final id = await AeroplaneStorage.instance.saveArchive(sampleState());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('archive_data_$id', '{broken json');

      expect(await AeroplaneStorage.instance.loadById(id), isNull);
      expect(await AeroplaneStorage.instance.loadLatest(), isNull);
    });

    test('状态字段非法的存档容错为无此档（模型校验抛错被基类吞掉）', () async {
      final id = await AeroplaneStorage.instance.saveArchive(sampleState());
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('archive_data_$id')!;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      (json['state'] as Map<String, dynamic>)['currentPlayer'] = 'purple';
      await prefs.setString('archive_data_$id', jsonEncode(json));

      expect(await AeroplaneStorage.instance.loadById(id), isNull);
    });
  });
}
