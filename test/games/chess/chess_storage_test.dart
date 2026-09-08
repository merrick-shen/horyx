import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/models/chess_game_state.dart';
import 'package:horyx/games/chess/models/chess_piece.dart';
import 'package:horyx/games/chess/services/chess_storage.dart';

void main() {
  setUp(() {
    // 每个测试使用独立的模拟存储，避免相互污染
    SharedPreferences.setMockInitialValues({});
  });

  /// 构造一个已走一手的对局状态（红马跳起），覆盖 moves 非空场景
  ChessGameState sampleState() {
    final board = ChessBoard.initial();
    final move = (from: (1, 0), to: (2, 2));
    board.applyMove(move);
    return ChessGameState(
      boardCode: board.encode(),
      turn: ChessColor.black,
      moves: [move],
      savedAt: DateTime(2026, 9, 8, 12, 30),
    );
  }

  group('ChessGameState 序列化', () {
    test('JSON 往返序列化数据一致（含走子序列）', () {
      final state = sampleState();

      final restored = ChessGameState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
      );

      expect(restored.boardCode, state.boardCode);
      expect(restored.turn, ChessColor.black);
      expect(restored.moves.single, state.moves.single);
      expect(restored.savedAt, state.savedAt);
    });

    test('开局状态（无走子序列、红先）往返一致', () {
      final state = ChessGameState(
        boardCode: ChessBoard.initial().encode(),
        turn: ChessColor.red,
        moves: const [],
        savedAt: DateTime(2026, 9, 8),
      );

      final restored = ChessGameState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
      );

      expect(restored.boardCode, state.boardCode);
      expect(restored.turn, ChessColor.red);
      expect(restored.moves, isEmpty);
      // 编码可还原为合法棋盘（借 ChessBoard.decode 的结构校验）
      expect(
        ChessBoard.decode(restored.boardCode).encode(),
        state.boardCode,
      );
    });

    test('board 字段缺失或长度不符抛出格式异常', () {
      final base = sampleState().toJson();
      expect(
        () => ChessGameState.fromJson(base..remove('board')),
        throwsFormatException,
      );

      final shortBoard = sampleState().toJson();
      shortBoard['board'] = (shortBoard['board'] as String).substring(0, 89);
      expect(
        () => ChessGameState.fromJson(shortBoard),
        throwsFormatException,
      );
    });

    test('turn 字段缺失或非法值抛出格式异常', () {
      final noTurn = sampleState().toJson()..remove('turn');
      expect(() => ChessGameState.fromJson(noTurn), throwsFormatException);

      final badTurn = sampleState().toJson();
      badTurn['turn'] = 'green';
      expect(() => ChessGameState.fromJson(badTurn), throwsFormatException);
    });

    test('moves 字段缺失或条目格式错误抛出格式异常', () {
      final noMoves = sampleState().toJson()..remove('moves');
      expect(() => ChessGameState.fromJson(noMoves), throwsFormatException);

      final badEntry = sampleState().toJson();
      badEntry['moves'] = [
        [1, 0, 2], // 三元而非四元
      ];
      expect(() => ChessGameState.fromJson(badEntry), throwsFormatException);
    });

    test('savedAt 无效时间字符串抛出格式异常', () {
      final badTime = sampleState().toJson();
      badTime['savedAt'] = 'not-a-date';
      expect(() => ChessGameState.fromJson(badTime), throwsFormatException);
    });
  });

  group('ChessStorage 存档服务', () {
    test('存储键正确', () {
      expect(ChessStorage.instance.storageKey, 'chess_unfinished_state');
    });

    test('无存档时 load 返回 null', () async {
      expect(await ChessStorage.instance.load(), isNull);
    });

    test('save 后 load 可完整还原', () async {
      final state = sampleState();
      await ChessStorage.instance.save(state);

      final loaded = await ChessStorage.instance.load();
      expect(loaded, isNotNull);
      expect(loaded!.boardCode, state.boardCode);
      expect(loaded.turn, ChessColor.black);
      expect(loaded.moves.single, state.moves.single);
      expect(loaded.savedAt, state.savedAt);
    });

    test('存档数据损坏时 load 容错返回 null', () async {
      final prefs = await SharedPreferences.getInstance();
      // 模拟半写/损坏数据
      await prefs.setString('chess_unfinished_state', '{broken json');
      expect(await ChessStorage.instance.load(), isNull);
    });

    test('clear 后存档清空', () async {
      await ChessStorage.instance.save(sampleState());
      await ChessStorage.instance.clear();
      expect(await ChessStorage.instance.load(), isNull);
    });
  });
}
