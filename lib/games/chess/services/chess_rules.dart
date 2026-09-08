import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/models/chess_piece.dart';

/// 象棋规则引擎（纯静态逻辑，无 UI 依赖）
/// 本地对局页与联机控制器共用，保证两侧规则永远同源。
///
/// 分阶段说明：
/// - 本阶段实现七类棋子的伪合法走法生成（只约束棋子自身规则与「不吃己子」）；
/// - 「走后己帅被将军」「将帅照面」的合法着法过滤由后续阶段接入
abstract final class ChessRules {
  /// 四个正交方向（车炮直线、帅直行共用）
  static const List<(int, int)> _orthogonal = [(1, 0), (-1, 0), (0, 1), (0, -1)];

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
    const jumps = [
      (1, 2), (-1, 2), (1, -2), (-1, -2),
      (2, 1), (-2, 1), (2, -1), (-2, -1),
    ];
    for (final (dx, dy) in jumps) {
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
}
