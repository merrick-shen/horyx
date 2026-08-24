import 'package:flutter_test/flutter_test.dart';
import 'package:horyx/services/gomoku/gomoku_rules.dart';

/// GomokuRules 五连判定单测
/// 落子序列索引奇偶决定颜色（偶=黑、奇=白），
/// 测试构造均模拟真实对局的黑白交替序列
void main() {
  // 标准黑五连序列：黑沿 xs 各列在 y 行横排，白子交替落别处（x=10 列）
  // 总手数 = 2*n-1（黑 n 子 + 白 n-1 子，黑先黑收）
  List<(int, int)> blackRow(int y, List<int> xs) => [
        for (var i = 0; i < 2 * xs.length - 1; i++)
          i.isEven ? (xs[i ~/ 2], y) : (10, 10 + i ~/ 2),
      ];

  test('横向恰好五连判胜', () {
    final moves = blackRow(7, [0, 1, 2, 3, 4]);
    expect(
      GomokuRules.hasFiveInRow(moves, 15, 4, 7, true),
      isTrue,
    );
  });

  test('竖向五连判胜', () {
    final moves = [
      (7, 0), (0, 10),
      (7, 1), (1, 10),
      (7, 2), (2, 10),
      (7, 3), (3, 10),
      (7, 4),
    ];
    expect(
      GomokuRules.hasFiveInRow(moves, 15, 7, 4, true),
      isTrue,
    );
  });

  test('主对角线（右下方向）五连判胜', () {
    final moves = [
      (0, 0), (0, 10),
      (1, 1), (1, 10),
      (2, 2), (2, 10),
      (3, 3), (3, 10),
      (4, 4),
    ];
    expect(
      GomokuRules.hasFiveInRow(moves, 15, 4, 4, true),
      isTrue,
    );
  });

  test('副对角线（右上方向）五连判胜', () {
    final moves = [
      (0, 4), (0, 10),
      (1, 3), (1, 10),
      (2, 2), (2, 10),
      (3, 1), (3, 10),
      (4, 0),
    ];
    expect(
      GomokuRules.hasFiveInRow(moves, 15, 4, 0, true),
      isTrue,
    );
  });

  test('白方五连判胜（奇索引执白）', () {
    final moves = [
      (10, 10), (0, 7),
      (10, 11), (1, 7),
      (10, 12), (2, 7),
      (10, 13), (3, 7),
      (10, 14), (4, 7),
    ];
    expect(
      GomokuRules.hasFiveInRow(moves, 15, 4, 7, false),
      isTrue,
    );
  });

  test('六连同样判胜（长连不禁手）', () {
    final moves = blackRow(7, [0, 1, 2, 3, 4, 5]);
    expect(
      GomokuRules.hasFiveInRow(moves, 15, 5, 7, true),
      isTrue,
    );
  });

  test('四连不判胜', () {
    final moves = blackRow(7, [0, 1, 2, 3]);
    expect(
      GomokuRules.hasFiveInRow(moves, 15, 3, 7, true),
      isFalse,
    );
  });

  test('边角起五连判胜（越界方向视为无子）', () {
    final moves = blackRow(0, [0, 1, 2, 3, 4]);
    expect(
      GomokuRules.hasFiveInRow(moves, 15, 0, 0, true),
      isTrue,
    );
  });

  test('中隔对方棋子的两段不判胜', () {
    // 黑 (0,0)(1,0)(2,0)(3,0) 与 (5,0)，(4,0) 为白子阻挡
    final moves = [
      (0, 0), (4, 0),
      (1, 0), (9, 9),
      (2, 0), (9, 10),
      (3, 0), (9, 11),
      (5, 0),
    ];
    expect(
      GomokuRules.hasFiveInRow(moves, 15, 5, 0, true),
      isFalse,
    );
  });
}
