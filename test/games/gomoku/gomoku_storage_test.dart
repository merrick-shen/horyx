import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:horyx/games/gomoku/models/gomoku_game_state.dart';
import 'package:horyx/games/gomoku/services/gomoku_storage.dart';

void main() {
  setUp(() {
    // 每个测试使用独立的模拟存储，避免相互污染
    SharedPreferences.setMockInitialValues({});
  });

  /// 构造一个已走两手的标准盘对局状态（黑先两子），覆盖 moves 非空场景
  GomokuGameState sampleState() {
    return GomokuGameState(
      boardSize: 15,
      moves: const [(7, 7), (8, 8)],
      savedAt: DateTime(2026, 9, 8, 12, 30),
    );
  }

  group('GomokuGameState 序列化', () {
    test('JSON 往返序列化数据一致（含落子序列）', () {
      final state = sampleState();

      final restored = GomokuGameState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
      );

      expect(restored.boardSize, state.boardSize);
      expect(restored.moves, state.moves);
      expect(restored.savedAt, state.savedAt);
    });

    test('开局状态（空落子序列）往返一致', () {
      final state = GomokuGameState(
        boardSize: 19,
        moves: const [],
        savedAt: DateTime(2026, 9, 8),
      );

      final restored = GomokuGameState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
      );

      expect(restored.boardSize, 19);
      expect(restored.moves, isEmpty);
      expect(restored.savedAt, state.savedAt);
    });

    test('moves 字段缺失或类型不符抛出格式异常', () {
      final noMoves = sampleState().toJson()..remove('moves');
      expect(() => GomokuGameState.fromJson(noMoves), throwsFormatException);

      final notList = sampleState().toJson();
      notList['moves'] = 'invalid';
      expect(() => GomokuGameState.fromJson(notList), throwsFormatException);
    });

    test('moves 条目结构错误抛出 Error（强转路径，非显式格式校验）', () {
      // 一元而非 [col, row] 二元：越界 RangeError
      final shortEntry = sampleState().toJson();
      shortEntry['moves'] = [
        [7],
      ];
      expect(
        () => GomokuGameState.fromJson(shortEntry),
        throwsA(isA<RangeError>()),
      );

      // 坐标非 int：强转 TypeError
      final badType = sampleState().toJson();
      badType['moves'] = [
        [7, 'x'],
      ];
      expect(
        () => GomokuGameState.fromJson(badType),
        throwsA(isA<TypeError>()),
      );
    });

    test('savedAt 无效时间字符串抛出格式异常', () {
      final badTime = sampleState().toJson();
      badTime['savedAt'] = 'not-a-date';
      expect(() => GomokuGameState.fromJson(badTime), throwsFormatException);
    });
  });

  group('GomokuStorage 存档服务', () {
    test('存储键正确', () {
      expect(GomokuStorage.instance.storageKey, 'gomoku_unfinished_state');
    });

    test('无存档时 load 返回 null', () async {
      expect(await GomokuStorage.instance.load(), isNull);
    });

    test('save 后 load 可完整还原', () async {
      final state = sampleState();
      await GomokuStorage.instance.save(state);

      final loaded = await GomokuStorage.instance.load();
      expect(loaded, isNotNull);
      expect(loaded!.boardSize, state.boardSize);
      expect(loaded.moves, state.moves);
      expect(loaded.savedAt, state.savedAt);
    });

    test('存档数据损坏时 load 容错返回 null', () async {
      final prefs = await SharedPreferences.getInstance();
      // 模拟半写/损坏数据
      await prefs.setString('gomoku_unfinished_state', '{broken json');
      expect(await GomokuStorage.instance.load(), isNull);
    });

    test('clear 后存档清空', () async {
      await GomokuStorage.instance.save(sampleState());
      await GomokuStorage.instance.clear();
      expect(await GomokuStorage.instance.load(), isNull);
    });
  });
}
