import 'package:flutter_test/flutter_test.dart';
import 'package:horyx/games/scoreboard/services/scoreboard_rules.dart';

/// ScoreboardRules 计分规则单测
/// 覆盖 BO 多数局与 deuce（平分后领先 2 分）两类规则边界
void main() {
  group('gamesToWin（BO 多数局）', () {
    test('BO1 需赢 1 局', () {
      expect(ScoreboardRules.gamesToWin(1), 1);
    });

    test('BO3 需赢 2 局', () {
      expect(ScoreboardRules.gamesToWin(3), 2);
    });

    test('BO5 需赢 3 局', () {
      expect(ScoreboardRules.gamesToWin(5), 3);
    });

    test('BO7 需赢 4 局', () {
      expect(ScoreboardRules.gamesToWin(7), 4);
    });
  });

  group('winsGame（每局胜负判定）', () {
    test('leadBy 为 0：到分即胜', () {
      // 11 分制无 deuce：得 11 分即胜，即便对方也有 10 分
      expect(ScoreboardRules.winsGame(11, 10, 11, 0), isTrue);
    });

    test('leadBy 为 0：未到分不判胜', () {
      expect(ScoreboardRules.winsGame(10, 5, 11, 0), isFalse);
    });

    test('deuce 规则：到达胜利分但分差不足不判胜', () {
      // 乒乓球 11 分制需领先 2 分：10:10 后得 11 分形成 11:10 仍不能赢
      expect(ScoreboardRules.winsGame(11, 10, 11, 2), isFalse);
    });

    test('deuce 规则：平分后拉开 2 分差距判胜', () {
      // 12:10 满足到分 + 领先 2 分
      expect(ScoreboardRules.winsGame(12, 10, 11, 2), isTrue);
    });

    test('deuce 规则：高分段延长赛同样需 2 分差', () {
      // 15:14 不判胜、15:13 判胜
      expect(ScoreboardRules.winsGame(15, 14, 11, 2), isFalse);
      expect(ScoreboardRules.winsGame(15, 13, 11, 2), isTrue);
    });

    test('恰好满足分差判胜（winScore 与 leadBy 同时到达）', () {
      // 21 分制领先 2：21:19 恰好双赢
      expect(ScoreboardRules.winsGame(21, 19, 21, 2), isTrue);
    });
  });
}
