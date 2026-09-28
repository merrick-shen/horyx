import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:horyx/games/word_pk/models/word_pk_entry.dart';
import 'package:horyx/games/word_pk/models/word_pk_game_state.dart';
import 'package:horyx/games/word_pk/pages/word_pk_page.dart';
import 'package:horyx/games/word_pk/services/word_pk_storage.dart';

void main() {
  setUp(() {
    // 每个测试使用独立的模拟存储，避免相互污染
    SharedPreferences.setMockInitialValues({});
  });

  group('WordPkGameState 序列化', () {
    test('JSON 往返序列化数据一致', () {
      final state = WordPkGameState(
        playerCount: 3,
        currentPlayer: 2,
        entries: const [
          WordPkEntry(word: 'banana', playerIndex: 2),
          WordPkEntry(word: 'apple', playerIndex: 1),
        ],
        savedAt: DateTime(2026, 8, 15, 12, 30),
      );

      final restored = WordPkGameState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
      );

      expect(restored.playerCount, 3);
      expect(restored.currentPlayer, 2);
      expect(restored.entries.length, 2);
      expect(restored.entries[0].word, 'banana');
      expect(restored.entries[1].playerIndex, 1);
      expect(restored.savedAt, state.savedAt);
    });

    test('字段缺失时抛出格式异常', () {
      expect(
        () => WordPkGameState.fromJson({'playerCount': 2}),
        throwsFormatException,
      );
    });
  });

  group('WordPkStorage 存档服务', () {
    test('无存档时 load 返回 null', () async {
      expect(await WordPkStorage.instance.load(), isNull);
    });

    test('save 后 load 可完整还原', () async {
      final state = WordPkGameState(
        playerCount: 2,
        currentPlayer: 2,
        entries: const [WordPkEntry(word: 'apple', playerIndex: 1)],
        savedAt: DateTime(2026, 8, 15),
      );
      await WordPkStorage.instance.save(state);

      final loaded = await WordPkStorage.instance.load();
      expect(loaded, isNotNull);
      expect(loaded!.playerCount, 2);
      expect(loaded.currentPlayer, 2);
      expect(loaded.entries.single.word, 'apple');
    });

    test('存档数据损坏时 load 容错返回 null', () async {
      final prefs = await SharedPreferences.getInstance();
      // 模拟半写/损坏数据
      await prefs.setString('word_pk_unfinished_state', '{broken json');
      expect(await WordPkStorage.instance.load(), isNull);
    });

    test('clear 后存档清空', () async {
      await WordPkStorage.instance.save(
        WordPkGameState(
          playerCount: 2,
          currentPlayer: 1,
          entries: const [],
          savedAt: DateTime(2026, 8, 15),
        ),
      );
      await WordPkStorage.instance.clear();
      expect(await WordPkStorage.instance.load(), isNull);
    });
  });

  group('WordPkStorage 多存档 API', () {
    WordPkGameState sampleState() {
      return WordPkGameState(
        playerCount: 3,
        currentPlayer: 2,
        entries: const [
          WordPkEntry(word: 'banana', playerIndex: 2),
          WordPkEntry(word: 'apple', playerIndex: 1),
        ],
        savedAt: DateTime(2026, 8, 15, 12, 30),
      );
    }

    test('gameId 与注册表登记名一致', () {
      expect(WordPkStorage.instance.gameId, WordPkPage.gameName);
    });

    test('saveArchive 新建后 loadLatest/loadById 可完整还原', () async {
      final state = sampleState();
      final id = await WordPkStorage.instance.saveArchive(state);

      final latest = await WordPkStorage.instance.loadLatest();
      expect(latest, isNotNull);
      expect(latest!.id, id);
      expect(latest.state.playerCount, 3);
      expect(latest.state.entries[0].word, 'banana');

      final byId = await WordPkStorage.instance.loadById(id);
      expect(byId!.state.savedAt, state.savedAt);
      expect(byId.state.summary, state.summary);
    });

    test('传入已有 id 覆盖：条目数不变、进度刷新', () async {
      final id = await WordPkStorage.instance.saveArchive(sampleState());
      final updated = WordPkGameState(
        playerCount: 2,
        currentPlayer: 1,
        entries: const [WordPkEntry(word: 'pear', playerIndex: 0)],
        savedAt: DateTime(2026, 8, 15, 18),
      );
      await WordPkStorage.instance.saveArchive(updated, id: id);

      final summaries = await WordPkStorage.instance.loadSummaries();
      expect(summaries, hasLength(1));
      expect(summaries.single.id, id);
      final record = await WordPkStorage.instance.loadById(id);
      expect(record!.state.playerCount, 2);
      expect(record.state.entries.single.word, 'pear');
    });

    test('remove 后恢复入口数据清空', () async {
      final id = await WordPkStorage.instance.saveArchive(sampleState());
      await WordPkStorage.instance.remove(id);
      expect(await WordPkStorage.instance.loadLatest(), isNull);
      expect(await WordPkStorage.instance.loadSummaries(), isEmpty);
    });
  });
}
