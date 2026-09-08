import 'package:flutter_test/flutter_test.dart';
import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/services/chess_rules.dart';

/// 阶段 2：七类棋子伪合法走法生成单测
/// 用 90 格棋盘编码构造手工局面（红大写黑小写、'.' 为空、row 0 为红方底线），
/// 断言仅覆盖走子生成，不含将军/照面过滤（阶段 3 接入）
void main() {
  /// 用每行 9 字符 × 10 行的棋盘图构造局面
  ChessBoard boardOf(List<String> rows) {
    expect(rows, hasLength(10), reason: '棋盘图必须为 10 行');
    final code = rows.join();
    expect(code, hasLength(90), reason: '每行必须为 9 字符');
    return ChessBoard.decode(code);
  }

  /// 走法终点集合，便于整体断言
  Set<(int, int)> destinations(List<ChessMove> moves) =>
      moves.map((m) => m.to).toSet();

  group('车：直线穿透', () {
    test('空盘四方向穿透，遇底线/边线/己帅止步', () {
      final board = boardOf([
        '....K....', // row 0 红帅
        '.........',
        '.........',
        '.........',
        '....R....', // row 4 红车
        '.........',
        '.........',
        '.........',
        '.........',
        '....k....', // row 9 黑将
      ]);
      final moves = ChessRules.movesFor(board, (4, 4));
      expect(moves, hasLength(16));
      expect(
        destinations(moves),
        {
          (4, 1), (4, 2), (4, 3), // 上（(4,0) 己帅阻挡）
          (4, 5), (4, 6), (4, 7), (4, 8), (4, 9), // 下至底线
          (0, 4), (1, 4), (2, 4), (3, 4), // 左
          (5, 4), (6, 4), (7, 4), (8, 4), // 右
        },
      );
    });

    test('直遇敌子可吃且不可越过', () {
      final board = boardOf([
        '....K....',
        '.........',
        '.........',
        '.........',
        '....R....',
        '....p....', // row 5 黑卒在车正下方
        '.........',
        '.........',
        '.........',
        '....k....',
      ]);
      final moves = ChessRules.movesFor(board, (4, 4));
      expect(destinations(moves), contains((4, 5)));
      expect(destinations(moves), isNot(contains((4, 6))));
    });

    test('直遇己子阻挡且不可吃', () {
      final board = boardOf([
        '....K....',
        '.........',
        '.........',
        '.........',
        '....R....',
        '....P....', // row 5 己方红兵阻挡（紧邻车）
        '.........',
        '.........',
        '.........',
        '....k....',
      ]);
      final moves = ChessRules.movesFor(board, (4, 4));
      expect(destinations(moves), isNot(contains((4, 5))));
      expect(destinations(moves), isNot(contains((4, 6))));
    });
  });

  group('炮：平走与隔子吃', () {
    test('直邻敌子无炮架不可吃', () {
      final board = boardOf([
        '....K....',
        '.........',
        '.........',
        '.........',
        '....C....', // row 4 红炮
        '....r....', // row 5 黑车直邻于下方向
        '.........',
        '.........',
        '.........',
        '...k.....', // row 9 黑将（避开炮的直线）
      ]);
      final moves = ChessRules.movesFor(board, (4, 4));
      // 下方向被直邻黑车堵死（不可吃、不可落、无炮架越吃），其余三方向空行
      expect(destinations(moves), isNot(contains((4, 5))));
      expect(destinations(moves), isNot(contains((4, 6))));
      expect(moves, hasLength(11));
    });

    test('隔一个炮架吃其后第一个敌子，炮架本身与更远子不可吃', () {
      final board = boardOf([
        '....K....',
        '.........',
        '.........',
        '.........',
        '....C....',
        '.........',
        '.........',
        '....p....', // row 7 黑卒作炮架
        '....r....', // row 8 黑车为可吃目标
        '...k.....',
      ]);
      final moves = ChessRules.movesFor(board, (4, 4));
      final dests = destinations(moves);
      expect(dests, contains((4, 6))); // 平走至炮架前
      expect(dests, contains((4, 8))); // 越过炮架吃黑车
      expect(dests, isNot(contains((4, 7)))); // 炮架不可吃
      expect(dests, isNot(contains((4, 9))));
      expect(moves, hasLength(14));
    });

    test('炮架后的己方棋子不可吃', () {
      final board = boardOf([
        '....K....',
        '.........',
        '.........',
        '.........',
        '....C....',
        '.........',
        '.........',
        '....p....', // 黑卒作炮架
        '....P....', // 己方红兵不可吃
        '...k.....',
      ]);
      final moves = ChessRules.movesFor(board, (4, 4));
      final dests = destinations(moves);
      expect(dests, contains((4, 6)));
      expect(dests, isNot(contains((4, 8))));
      expect(moves, hasLength(13));
    });
  });

  group('马：日字与蹩马腿', () {
    test('中心空盘八向全通', () {
      final board = boardOf([
        '....K....',
        '.........',
        '.........',
        '.........',
        '....N....', // row 4 红马
        '.........',
        '.........',
        '.........',
        '.........',
        '....k....',
      ]);
      expect(
        destinations(ChessRules.movesFor(board, (4, 4))),
        {
          (5, 6), (3, 6), (5, 2), (3, 2),
          (6, 5), (2, 5), (6, 3), (2, 3),
        },
      );
    });

    test('纵腿被塞：同一轴向的两跳全部被蹩', () {
      final board = boardOf([
        '....K....',
        '.........',
        '.........',
        '....P....', // row 3 红兵塞纵腿（(4,4) 马的 (0,-1) 邻格）
        '....N....',
        '.........',
        '.........',
        '.........',
        '.........',
        '....k....',
      ]);
      final dests = destinations(ChessRules.movesFor(board, (4, 4)));
      expect(dests, isNot(contains((5, 2))));
      expect(dests, isNot(contains((3, 2))));
      expect(dests, contains((5, 6))); // 反向不受影响
      expect(dests, hasLength(6));
    });

    test('横腿被塞：同一轴向的两跳全部被蹩', () {
      final board = boardOf([
        '....K....',
        '.........',
        '.........',
        '.........',
        '....NP...', // row 4 红兵塞横腿（(1,0) 邻格）
        '.........',
        '.........',
        '.........',
        '.........',
        '....k....',
      ]);
      final dests = destinations(ChessRules.movesFor(board, (4, 4)));
      expect(dests, isNot(contains((6, 5))));
      expect(dests, isNot(contains((6, 3))));
      expect(dests, contains((2, 5)));
      expect(dests, hasLength(6));
    });
  });

  group('相/象：田字、塞象眼与不过河', () {
    test('红相在中路，四个田字位全通', () {
      final board = boardOf([
        '....K....',
        '.........',
        '....B....', // row 2 红相
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '....k....',
      ]);
      expect(
        destinations(ChessRules.movesFor(board, (4, 2))),
        {(2, 0), (6, 0), (2, 4), (6, 4)},
      );
    });

    test('红相不得过河（目标 row ≥ 5 被过滤）', () {
      final board = boardOf([
        '....K....',
        '.........',
        '.........',
        '.........',
        '..B......', // row 4 红相在河边
        '.........',
        '.........',
        '.........',
        '.........',
        '....k....',
      ]);
      final dests = destinations(ChessRules.movesFor(board, (2, 4)));
      expect(dests, {(4, 2), (0, 2)});
    });

    test('田字中心有子（塞象眼）该方向不可走', () {
      final board = boardOf([
        '....K....',
        '...P.....', // row 1 红兵塞 (2,0) 方向的象眼
        '....B....',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '....k....',
      ]);
      final dests = destinations(ChessRules.movesFor(board, (4, 2)));
      expect(dests, isNot(contains((2, 0))));
      expect(dests, {(6, 0), (2, 4), (6, 4)});
    });

    test('黑象对称：不得过河（目标 row ≤ 4 被过滤）', () {
      final board = boardOf([
        '....K....',
        '.........',
        '.........',
        '.........',
        '.........',
        '..b......', // row 5 黑象在河边
        '.........',
        '.........',
        '.........',
        '....k....',
      ]);
      final dests = destinations(ChessRules.movesFor(board, (2, 5)));
      expect(dests, {(4, 7), (0, 7)});
    });
  });

  group('仕/士：九宫斜行', () {
    test('宫中心四斜向全通', () {
      final board = boardOf([
        '....K....',
        '....A....', // row 1 红仕
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '....k....',
      ]);
      expect(
        destinations(ChessRules.movesFor(board, (4, 1))),
        {(3, 0), (5, 0), (3, 2), (5, 2)},
      );
    });

    test('宫角只能斜向宫心，出宫/出界方向被过滤', () {
      final board = boardOf([
        '...AK....', // row 0 红仕 (3,0)、红帅 (4,0)
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '....k....',
      ]);
      expect(destinations(ChessRules.movesFor(board, (3, 0))), {(4, 1)});
    });

    test('黑士对称：宫内四斜向', () {
      final board = boardOf([
        '....K....',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '....a....', // row 8 黑士
        '....k....',
      ]);
      expect(
        destinations(ChessRules.movesFor(board, (4, 8))),
        {(3, 7), (5, 7), (3, 9), (5, 9)},
      );
    });
  });

  group('帅/将：九宫直行', () {
    test('红帅在底线：三个方向可走，出宫/出界被过滤', () {
      final board = boardOf([
        '....K....',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '....k....',
      ]);
      expect(
        destinations(ChessRules.movesFor(board, (4, 0))),
        {(3, 0), (5, 0), (4, 1)},
      );
    });

    test('可吃进入九宫的敌子', () {
      final board = boardOf([
        '...pK....', // row 0 黑卒闯入宫内
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '....k....',
      ]);
      final dests = destinations(ChessRules.movesFor(board, (4, 0)));
      expect(dests, {(3, 0), (5, 0), (4, 1)});
    });

    test('黑将对称：底线三方向', () {
      final board = boardOf([
        '....K....',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '....k....',
      ]);
      expect(
        destinations(ChessRules.movesFor(board, (4, 9))),
        {(3, 9), (5, 9), (4, 8)},
      );
    });
  });

  group('兵/卒：过河前后', () {
    test('红兵未过河只能前进一格', () {
      final board = boardOf([
        '....K....',
        '.........',
        '.........',
        '....P....', // row 3 红兵
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '....k....',
      ]);
      expect(destinations(ChessRules.movesFor(board, (4, 3))), {(4, 4)});
    });

    test('红兵过河后可进可横', () {
      final board = boardOf([
        '....K....',
        '.........',
        '.........',
        '.........',
        '.........',
        '....P....', // row 5 红兵已过河
        '.........',
        '.........',
        '.........',
        '....k....',
      ]);
      expect(
        destinations(ChessRules.movesFor(board, (4, 5))),
        {(4, 6), (3, 5), (5, 5)},
      );
    });

    test('红兵到达底线后只能横移（前进方向出界）', () {
      final board = boardOf([
        '....K....',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '..P..k...', // row 9 红兵 (2,9)、黑将 (4,9)
      ]);
      expect(destinations(ChessRules.movesFor(board, (2, 9))), {(1, 9), (3, 9)});
    });

    test('过河红兵可横吃敌子、不吃己子', () {
      final board = boardOf([
        '....K....',
        '.........',
        '.........',
        '.........',
        '.........',
        '...pP....', // row 5 黑卒 (3,5) 可吃、红兵 (4,5)
        '.........',
        '.........',
        '.........',
        '....k....',
      ]);
      final dests = destinations(ChessRules.movesFor(board, (4, 5)));
      expect(dests, {(4, 6), (3, 5), (5, 5)});
    });

    test('黑卒对称：未过河只进、过河可横', () {
      final board = boardOf([
        '....K....',
        '.........',
        '.........',
        '.........',
        '....p....', // row 4 黑卒已过河
        '.........',
        '....p....', // row 6 黑卒未过河
        '.........',
        '.........',
        '....k....',
      ]);
      expect(destinations(ChessRules.movesFor(board, (4, 6))), {(4, 5)});
      expect(
        destinations(ChessRules.movesFor(board, (4, 4))),
        {(4, 3), (3, 4), (5, 4)},
      );
    });
  });
}
