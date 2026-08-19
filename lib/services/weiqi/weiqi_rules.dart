/// 落子校验结果
enum WeiqiPlaceResult {
  /// 合法落子（可能伴随提子）
  ok,

  /// 目标交叉点已有棋子
  occupied,

  /// 自杀手：落子后己方棋块无气且未提掉任何对方棋子
  suicide,

  /// 禁全同：落子后局面重现历史局面（打劫立即回提 / 循环长生）
  repetition,
}

/// 围棋规则引擎（纯静态逻辑，无 UI 依赖）
/// 采用中国规则：
/// - 打劫以「禁全同」（superko）判定：任何落子不得重现历史局面，
///   同时天然禁止循环长生等无限循环
/// - 终局以数子法计点：己方棋子数 + 仅己方围住的空域点数，公气不计
/// - 贴目固定 7.5（中国规则黑贴 3.75 子的等效目数）；9/13 路无官方
///   统一贴目值，沿用同一数值保持规则简单
/// 注意：引擎不判断死活——终局数子按盘面直接计算，面对面对局中
/// 双方应在双虚手前将死子提净（与实体棋盘的对局习惯一致）
abstract final class WeiqiRules {
  /// 黑方贴目（目/点）
  static const double komi = 7.5;

  /// 尝试落子：合法时返回新棋盘与提子数；非法时返回原因且棋盘不变
  ///
  /// [board] 一维棋盘（0 空 / 1 黑 / 2 白），index = row * size + col
  /// [history] 落子前的历史局面序列化集合（含当前局面），用于禁全同判定
  static (WeiqiPlaceResult, List<int>, int) tryPlace(
    List<int> board,
    int size,
    int col,
    int row,
    bool black,
    Set<String> history,
  ) {
    final index = row * size + col;
    if (board[index] != 0) {
      return (WeiqiPlaceResult.occupied, board, 0);
    }

    final color = black ? 1 : 2;
    final opponent = black ? 2 : 1;
    final next = List<int>.of(board);
    next[index] = color;

    // 先提对方无气棋块：落子可能同时打吃多个相邻对方块，逐块洪泛判定
    // （前一块被提后棋盘更新，后续块在此棋盘上继续判定，顺序处理即正确）
    var captured = 0;
    for (final n in _neighborIndexes(col, row, size)) {
      if (next[n] != opponent) continue;
      final group = _collectGroup(next, size, n);
      if (group.liberties == 0) {
        for (final s in group.stones) {
          next[s] = 0;
        }
        captured += group.stones.length;
      }
    }

    // 自杀判定：未提子且己方棋块无气
    final mine = _collectGroup(next, size, index);
    if (mine.liberties == 0) {
      return (WeiqiPlaceResult.suicide, board, 0);
    }

    // 禁全同判定：不提子的落子必然产生新局面，此处命中必为打劫/循环
    if (history.contains(serialize(next))) {
      return (WeiqiPlaceResult.repetition, board, 0);
    }

    return (WeiqiPlaceResult.ok, next, captured);
  }

  /// 数子法计点：返回 (黑点, 白点)
  /// 己方棋子数 + 仅接触己方颜色的空域点数；
  /// 双方都接触的空点为公气，不计入任何一方
  static (int, int) score(List<int> board, int size) {
    var blackPoints = 0;
    var whitePoints = 0;
    final visited = List<bool>.filled(board.length, false);

    for (var i = 0; i < board.length; i++) {
      if (board[i] == 1) {
        blackPoints++;
      } else if (board[i] == 2) {
        whitePoints++;
      } else if (!visited[i]) {
        // 空点洪泛：收集整个空域及其接触到的颜色
        final region = <int>[i];
        final touches = <int>{};
        final queue = <int>[i];
        visited[i] = true;
        while (queue.isNotEmpty) {
          final cur = queue.removeLast();
          final col = cur % size;
          final row = cur ~/ size;
          for (final n in _neighborIndexes(col, row, size)) {
            if (board[n] == 0) {
              if (!visited[n]) {
                visited[n] = true;
                region.add(n);
                queue.add(n);
              }
            } else {
              touches.add(board[n]);
            }
          }
        }
        // 空域仅接触单一颜色时归该方，公气双方接触不计
        if (touches.length == 1) {
          if (touches.single == 1) {
            blackPoints += region.length;
          } else {
            whitePoints += region.length;
          }
        }
      }
    }
    return (blackPoints, whitePoints);
  }

  /// 局面序列化（禁全同比较键）
  static String serialize(List<int> board) => board.join(',');

  /// 交叉点四邻的一维索引（棋盘边缘越界方向自动忽略）
  static Iterable<int> _neighborIndexes(int col, int row, int size) sync* {
    if (col > 0) yield row * size + col - 1;
    if (col < size - 1) yield row * size + col + 1;
    if (row > 0) yield (row - 1) * size + col;
    if (row < size - 1) yield (row + 1) * size + col;
  }

  /// 洪泛收集起始点所在棋块：返回棋子索引列表与气数
  static ({List<int> stones, int liberties}) _collectGroup(
    List<int> board,
    int size,
    int start,
  ) {
    final color = board[start];
    final stones = <int>[start];
    final seen = <int>{start};
    final liberties = <int>{};
    final queue = <int>[start];

    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      final col = cur % size;
      final row = cur ~/ size;
      for (final n in _neighborIndexes(col, row, size)) {
        final value = board[n];
        if (value == 0) {
          liberties.add(n);
        } else if (value == color && seen.add(n)) {
          stones.add(n);
          queue.add(n);
        }
      }
    }
    return (stones: stones, liberties: liberties.length);
  }
}
