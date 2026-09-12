import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/models/chess_piece.dart';

/// 对局终局原因
/// 将死/困毙由局面判定（judgeEnd）；认输由对局流程直接设置，不参与局面判定
enum ChessEndReason {
  checkmate, // 将死：被将军且无任何合法着法
  stalemate, // 困毙：未被将军但无任何合法着法（中国象棋中判负，非和棋）
  resign, // 认输
}

/// 象棋规则引擎（纯静态逻辑，无 UI 依赖）
/// 本地对局页与联机控制器共用，保证两侧规则永远同源。
///
/// 分阶段说明：
/// - 本阶段实现七类棋子的伪合法走法生成（只约束棋子自身规则与「不吃己子」）；
/// - 「走后己帅被将军」「将帅照面」的合法着法过滤由后续阶段接入
abstract final class ChessRules {
  /// 四个正交方向（车炮直线、帅直行共用）
  static const List<(int, int)> _orthogonal = [(1, 0), (-1, 0), (0, 1), (0, -1)];

  /// 马的八个日字偏移（走子生成与攻击检测反向查询共用）
  static const List<(int, int)> _knightJumps = [
    (1, 2), (-1, 2), (1, -2), (-1, -2),
    (2, 1), (-2, 1), (2, -1), (-2, -1),
  ];

  /// 生成 [pos] 处棋子的伪合法走法
  ///
  /// 「伪合法」= 满足棋子自身走子规则、目标格非己方棋子；
  /// 不含自杀着法与将帅照面过滤（由合法着法过滤阶段处理）
  static List<ChessMove> movesFor(ChessBoard board, ChessPos pos) {
    final piece = board.pieceAt(pos);
    assert(piece != null, 'movesFor 的起点无棋子：$pos');
    return switch (piece!.type) {
      ChessPieceType.rook => _rookMoves(board, pos, piece.color),
      ChessPieceType.cannon => _cannonMoves(board, pos, piece.color),
      ChessPieceType.knight => _knightMoves(board, pos, piece.color),
      ChessPieceType.bishop => _bishopMoves(board, pos, piece.color),
      ChessPieceType.advisor => _advisorMoves(board, pos, piece.color),
      ChessPieceType.king => _kingMoves(board, pos, piece.color),
      ChessPieceType.pawn => _pawnMoves(board, pos, piece.color),
    };
  }

  static bool _inBoard(int col, int row) =>
      col >= 0 && col < ChessBoard.cols && row >= 0 && row < ChessBoard.rows;

  /// 九宫判定：col 3-5；红方 row 0-2、黑方 row 7-9
  static bool _inPalace(int col, int row, ChessColor color) =>
      col >= 3 && col <= 5 && (color == ChessColor.red ? row <= 2 : row >= 7);

  /// 目标格在盘内且非己方棋子时收进走法列表（方向性棋子共用的落点过滤）
  static void _addTarget(
    List<ChessMove> moves,
    ChessBoard board,
    ChessPos from,
    ChessPos to,
    ChessColor color,
  ) {
    final (col, row) = to;
    if (!_inBoard(col, row)) return;
    final target = board.pieceAt(to);
    if (target != null && target.color == color) return;
    moves.add((from: from, to: to));
  }

  /// 车：四方向直线穿透，遇到的第一个子即可达边界（敌方可吃、己方阻挡）
  static List<ChessMove> _rookMoves(ChessBoard board, ChessPos from, ChessColor color) {
    final moves = <ChessMove>[];
    for (final (dx, dy) in _orthogonal) {
      var col = from.$1 + dx;
      var row = from.$2 + dy;
      while (_inBoard(col, row)) {
        final target = board.pieceAt((col, row));
        if (target != null) {
          if (target.color != color) moves.add((from: from, to: (col, row)));
          break;
        }
        moves.add((from: from, to: (col, row)));
        col += dx;
        row += dy;
      }
    }
    return moves;
  }

  /// 炮：平走段与车相同但不能吃直邻子；吃子必须隔恰好一个炮架
  static List<ChessMove> _cannonMoves(ChessBoard board, ChessPos from, ChessColor color) {
    final moves = <ChessMove>[];
    for (final (dx, dy) in _orthogonal) {
      // 第一段：空格平走，遇子（炮架候选）停下
      var col = from.$1 + dx;
      var row = from.$2 + dy;
      while (_inBoard(col, row) && board.pieceAt((col, row)) == null) {
        moves.add((from: from, to: (col, row)));
        col += dx;
        row += dy;
      }
      // 第二段：越过炮架继续找第一个子，该子是唯一可能被吃的目标（敌方才行）
      col += dx;
      row += dy;
      while (_inBoard(col, row)) {
        final target = board.pieceAt((col, row));
        if (target != null) {
          if (target.color != color) moves.add((from: from, to: (col, row)));
          break;
        }
        col += dx;
        row += dy;
      }
    }
    return moves;
  }

  /// 马：八个日字位；先沿位移较大（绝对值 2）的轴向走一步即为马腿，
  /// 腿上有子则该轴向上的两跳全部被蹩
  static List<ChessMove> _knightMoves(ChessBoard board, ChessPos from, ChessColor color) {
    final moves = <ChessMove>[];
    for (final (dx, dy) in _knightJumps) {
      final legCol = from.$1 + (dx.abs() == 2 ? dx ~/ 2 : 0);
      final legRow = from.$2 + (dy.abs() == 2 ? dy ~/ 2 : 0);
      // 腿格盘外时目标必在盘外，一并跳过
      if (!_inBoard(legCol, legRow) || board.pieceAt((legCol, legRow)) != null) {
        continue;
      }
      _addTarget(moves, board, from, (from.$1 + dx, from.$2 + dy), color);
    }
    return moves;
  }

  /// 相/象：田字对角两步 + 塞象眼 + 不过河（红方不得越过 row 4，黑方不得低于 row 5）
  static List<ChessMove> _bishopMoves(ChessBoard board, ChessPos from, ChessColor color) {
    final moves = <ChessMove>[];
    const diagonals = [(2, 2), (2, -2), (-2, 2), (-2, -2)];
    for (final (dx, dy) in diagonals) {
      final toCol = from.$1 + dx;
      final toRow = from.$2 + dy;
      // 目标出界直接跳过：底线象的越界田字方向连象眼都在盘外，需先于眼检查拦截
      if (!_inBoard(toCol, toRow)) continue;
      // 塞象眼：田字中心（对角中点）有子则不可走
      if (board.pieceAt((from.$1 + dx ~/ 2, from.$2 + dy ~/ 2)) != null) continue;
      // 不过河：红象活动于 row 0-4，黑象活动于 row 5-9
      if (color == ChessColor.red ? toRow > 4 : toRow < 5) continue;
      _addTarget(moves, board, from, (toCol, toRow), color);
    }
    return moves;
  }

  /// 仕/士：九宫内斜行一步
  static List<ChessMove> _advisorMoves(ChessBoard board, ChessPos from, ChessColor color) {
    final moves = <ChessMove>[];
    const diagonals = [(1, 1), (1, -1), (-1, 1), (-1, -1)];
    for (final (dx, dy) in diagonals) {
      final to = (from.$1 + dx, from.$2 + dy);
      if (_inPalace(to.$1, to.$2, color)) {
        _addTarget(moves, board, from, to, color);
      }
    }
    return moves;
  }

  /// 帅/将：九宫内直行一步（将帅照面约束在合法着法过滤阶段处理）
  static List<ChessMove> _kingMoves(ChessBoard board, ChessPos from, ChessColor color) {
    final moves = <ChessMove>[];
    for (final (dx, dy) in _orthogonal) {
      final to = (from.$1 + dx, from.$2 + dy);
      if (_inPalace(to.$1, to.$2, color)) {
        _addTarget(moves, board, from, to, color);
      }
    }
    return moves;
  }

  /// 兵/卒：过河前只进；过河后可进可横（永不后退）
  /// 红方向 row 增大方向前进、row 5 起算过河；黑方相反
  static List<ChessMove> _pawnMoves(ChessBoard board, ChessPos from, ChessColor color) {
    final moves = <ChessMove>[];
    final forward = color == ChessColor.red ? 1 : -1;
    final crossed = color == ChessColor.red ? from.$2 >= 5 : from.$2 <= 4;
    final candidates = <(int, int)>[
      (0, forward),
      if (crossed) (1, 0),
      if (crossed) (-1, 0),
    ];
    for (final (dx, dy) in candidates) {
      _addTarget(moves, board, from, (from.$1 + dx, from.$2 + dy), color);
    }
    return moves;
  }

  // ---------------------------------------------------------------------------
  // 攻击检测与合法着法过滤
  // ---------------------------------------------------------------------------

  /// 查找某方帅/将的位置（王唯一性由开局与存档结构校验保证）
  static ChessPos _findKing(ChessBoard board, ChessColor color) {
    for (var row = 0; row < ChessBoard.rows; row++) {
      for (var col = 0; col < ChessBoard.cols; col++) {
        final p = board.pieceAt((col, row));
        if (p != null && p.color == color && p.type == ChessPieceType.king) {
          return (col, row);
        }
      }
    }
    throw StateError('找不到 $color 方的帅/将');
  }

  /// [pos] 是否被 [byColor] 一方攻击（可被其下一手吃到）
  ///
  /// 覆盖：车（直线直达）、炮（隔恰好一子）、马（反向日字 + 蹩腿）、
  /// 兵/卒（前进 + 过河横移）、帅/将（九宫内直邻）。
  /// 相/仕不纳入：它们活动不出自方半场/九宫，永远攻击不到对方九宫，
  /// 对「王是否被将军」的判定无影响，省去可简化检测
  static bool isSquareAttacked(ChessBoard board, ChessPos pos, ChessColor byColor) {
    final (col, row) = pos;

    // pos 上是 byColor 自己的子时不可能被 byColor 攻击（己方子不可被己方吃），
    // 否则直线系会把「己方车/炮贴着己方子」误判为攻击
    final occupant = board.pieceAt(pos);
    if (occupant != null && occupant.color == byColor) return false;

    // 直线系：每方向第一个子若是 byColor 的车则攻击；
    // 第二个子若是 byColor 的炮（中间恰好一个遮挡）则攻击
    for (final (dx, dy) in _orthogonal) {
      var c = col + dx;
      var r = row + dy;
      var firstSeen = false;
      while (_inBoard(c, r)) {
        final p = board.pieceAt((c, r));
        if (p != null) {
          if (!firstSeen) {
            if (p.color == byColor && p.type == ChessPieceType.rook) return true;
            firstSeen = true;
          } else {
            if (p.color == byColor && p.type == ChessPieceType.cannon) return true;
            break;
          }
        }
        c += dx;
        r += dy;
      }
    }

    // 马：候选马位在日字偏移处，蹩腿位（马位朝目标的主轴一步）无子即构成攻击
    for (final (dx, dy) in _knightJumps) {
      final mCol = col + dx;
      final mRow = row + dy;
      if (!_inBoard(mCol, mRow)) continue;
      final p = board.pieceAt((mCol, mRow));
      if (p == null || p.color != byColor || p.type != ChessPieceType.knight) {
        continue;
      }
      final legCol = dx.abs() == 2 ? mCol - dx ~/ 2 : mCol;
      final legRow = dy.abs() == 2 ? mRow - dy ~/ 2 : mRow;
      if (board.pieceAt((legCol, legRow)) == null) return true;
    }

    // 兵/卒：byColor 兵攻击 X = 兵在其前进方向邻格，或（该兵已过河）左右横移邻格
    if (byColor == ChessColor.red) {
      if (_inBoard(col, row - 1)) {
        final p = board.pieceAt((col, row - 1));
        if (p != null && p.color == ChessColor.red && p.type == ChessPieceType.pawn) {
          return true;
        }
      }
      if (row >= 5) {
        for (final dc in const [-1, 1]) {
          if (!_inBoard(col + dc, row)) continue;
          final p = board.pieceAt((col + dc, row));
          if (p != null && p.color == ChessColor.red && p.type == ChessPieceType.pawn) {
            return true;
          }
        }
      }
    } else {
      if (_inBoard(col, row + 1)) {
        final p = board.pieceAt((col, row + 1));
        if (p != null && p.color == ChessColor.black && p.type == ChessPieceType.pawn) {
          return true;
        }
      }
      if (row <= 4) {
        for (final dc in const [-1, 1]) {
          if (!_inBoard(col + dc, row)) continue;
          final p = board.pieceAt((col + dc, row));
          if (p != null && p.color == ChessColor.black && p.type == ChessPieceType.pawn) {
            return true;
          }
        }
      }
    }

    // 帅/将：byColor 王在九宫内直邻一格攻击（王吃不到宫外子，故要求 X 在其九宫内）
    if (_inPalace(col, row, byColor)) {
      for (final (dx, dy) in _orthogonal) {
        if (!_inBoard(col + dx, row + dy)) continue;
        final p = board.pieceAt((col + dx, row + dy));
        if (p != null && p.color == byColor && p.type == ChessPieceType.king) {
          return true;
        }
      }
    }

    return false;
  }

  /// 将帅照面：两王同列且中间无遮挡
  /// 中国象棋中形成照面的走法不合法；缺王（对局已终结的中间态）不视为照面
  static bool kingsFacing(ChessBoard board) {
    ChessPos? redKing;
    ChessPos? blackKing;
    for (var row = 0; row < ChessBoard.rows; row++) {
      for (var col = 0; col < ChessBoard.cols; col++) {
        final p = board.pieceAt((col, row));
        if (p == null || p.type != ChessPieceType.king) continue;
        if (p.color == ChessColor.red) {
          redKing = (col, row);
        } else {
          blackKing = (col, row);
        }
      }
    }
    if (redKing == null || blackKing == null) return false;
    if (redKing.$1 != blackKing.$1) return false;
    // 沿两王之间的行区间（取较小行到较大行）逐格查遮挡；
    // 不假定红下黑上的行序，避免非常规局面下区间为空导致误判
    final col = redKing.$1;
    final from = redKing.$2 < blackKing.$2 ? redKing.$2 : blackKing.$2;
    final to = redKing.$2 < blackKing.$2 ? blackKing.$2 : redKing.$2;
    for (var r = from + 1; r < to; r++) {
      if (board.pieceAt((col, r)) != null) return false;
    }
    return true;
  }

  /// [color] 方是否正被将军（其帅/将被对方攻击），供对局页将军提示共用
  static bool isInCheck(ChessBoard board, ChessColor color) {
    final enemy = color == ChessColor.red ? ChessColor.black : ChessColor.red;
    return isSquareAttacked(board, _findKing(board, color), enemy);
  }

  /// [pos] 处棋子的合法着法：伪合法走法过滤「走后己帅被将军」与「走后将帅照面」
  /// 被将军时天然只剩解将着法（走后仍被将军的一律滤除）
  static List<ChessMove> legalMovesFor(ChessBoard board, ChessPos pos) {
    final piece = board.pieceAt(pos);
    assert(piece != null, 'legalMovesFor 的起点无棋子：$pos');
    final enemy = piece!.color == ChessColor.red ? ChessColor.black : ChessColor.red;
    final result = <ChessMove>[];
    for (final move in movesFor(board, pos)) {
      final captured = board.applyMove(move);
      final kingPos = _findKing(board, piece.color);
      final illegal =
          isSquareAttacked(board, kingPos, enemy) || kingsFacing(board);
      board.revertMove(move, captured);
      if (!illegal) result.add(move);
    }
    return result;
  }

  /// 终局判定：[colorToMove] 方是否已无路可走
  ///
  /// 返回 null 表示对局继续；否则该方被判负（胜方为对方）：
  /// - [ChessEndReason.checkmate]：被将军且无任何合法着法（将死）
  /// - [ChessEndReason.stalemate]：未被将军但无任何合法着法（困毙，判负）
  static ChessEndReason? judgeEnd(ChessBoard board, ChessColor colorToMove) {
    for (var row = 0; row < ChessBoard.rows; row++) {
      for (var col = 0; col < ChessBoard.cols; col++) {
        final p = board.pieceAt((col, row));
        if (p == null || p.color != colorToMove) continue;
        // 任一子存在合法着法即对局继续（合法着法内部已含将军/照面过滤）
        if (legalMovesFor(board, (col, row)).isNotEmpty) return null;
      }
    }
    return isInCheck(board, colorToMove)
        ? ChessEndReason.checkmate
        : ChessEndReason.stalemate;
  }
}
