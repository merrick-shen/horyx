import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:horyx/games/scoreboard/models/scoreboard_game_state.dart';
import 'package:horyx/games/scoreboard/services/scoreboard_storage.dart';

void main() {
  setUp(() {
    // 每个测试使用独立的模拟存储，避免相互污染
    SharedPreferences.setMockInitialValues({});
  });

  /// 构造一个局进行中的计分状态（BO3 + 撤销快照栈），覆盖核心字段
  ScoreboardGameState sampleState() {
    return ScoreboardGameState(
      bestOf: 3,
      winScore: 11,
      leadBy: 2,
      redGames: 1,
      blueGames: 0,
      redScore: 8,
      blueScore: 5,
      history: const [
        [0, 0, 0, 0],
        [0, 0, 3, 1],
      ],
      gameOver: false,
      savedAt: DateTime(2026, 9, 8, 12, 30),
    );
  }

  group('ScoreboardGameState 序列化', () {
    test('JSON 往返序列化数据一致（含撤销快照栈）', () {
      final state = sampleState();

      final restored = ScoreboardGameState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
      );

      expect(restored.bestOf, state.bestOf);
      expect(restored.winScore, state.winScore);
      expect(restored.leadBy, state.leadBy);
      expect(restored.redGames, state.redGames);
      expect(restored.blueGames, state.blueGames);
      expect(restored.redScore, state.redScore);
      expect(restored.blueScore, state.blueScore);
      expect(restored.history, state.history);
      expect(restored.gameOver, state.gameOver);
      expect(restored.savedAt, state.savedAt);
    });

    test('gameOver 字段缺失（旧存档）按局进行中兼容处理', () {
      final legacy = sampleState().toJson()..remove('gameOver');

      final restored = ScoreboardGameState.fromJson(legacy);

      expect(restored.gameOver, isFalse);
    });

    test('gameOver=true（本局已分出胜负）往返一致', () {
      final state = ScoreboardGameState(
        bestOf: 3,
        winScore: 11,
        leadBy: 2,
        redGames: 1,
        blueGames: 0,
        redScore: 11,
        blueScore: 7,
        history: const [],
        gameOver: true,
        savedAt: DateTime(2026, 9, 8),
      );

      final restored = ScoreboardGameState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
      );

      expect(restored.gameOver, isTrue);
      expect(restored.history, isEmpty);
    });

    test('score 字段缺失抛出类型异常（强转路径，非显式格式校验）', () {
      final noScore = sampleState().toJson()..remove('redScore');
      expect(
        () => ScoreboardGameState.fromJson(noScore),
        throwsA(isA<TypeError>()),
      );
    });

    test('savedAt 无效时间字符串抛出格式异常', () {
      final badTime = sampleState().toJson();
      badTime['savedAt'] = 'not-a-date';
      expect(
        () => ScoreboardGameState.fromJson(badTime),
        throwsFormatException,
      );
    });
  });

  group('ScoreboardStorage 存档服务', () {
    test('存储键正确', () {
      expect(
        ScoreboardStorage.instance.storageKey,
        'scoreboard_unfinished_state',
      );
    });

    test('无存档时 load 返回 null', () async {
      expect(await ScoreboardStorage.instance.load(), isNull);
    });

    test('save 后 load 可完整还原', () async {
      final state = sampleState();
      await ScoreboardStorage.instance.save(state);

      final loaded = await ScoreboardStorage.instance.load();
      expect(loaded, isNotNull);
      expect(loaded!.bestOf, state.bestOf);
      expect(loaded.history, state.history);
      expect(loaded.gameOver, state.gameOver);
      expect(loaded.savedAt, state.savedAt);
    });

    test('存档数据损坏时 load 容错返回 null', () async {
      final prefs = await SharedPreferences.getInstance();
      // 模拟半写/损坏数据
      await prefs.setString('scoreboard_unfinished_state', '{broken json');
      expect(await ScoreboardStorage.instance.load(), isNull);
    });

    test('clear 后存档清空', () async {
      await ScoreboardStorage.instance.save(sampleState());
      await ScoreboardStorage.instance.clear();
      expect(await ScoreboardStorage.instance.load(), isNull);
    });
  });
}
