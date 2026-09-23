import 'package:horyx/games/chess/models/chess_piece.dart';

/// 象棋坐标：col 0-8（红方视角从左到右），row 0-9（row 0 为红方底线、row 9 为黑方底线）
/// 全项目统一此坐标系：规则引擎、UI 坐标换算、存档序列化均以它为准
typedef ChessPos = (int col, int row);

/// 一步走子：起点 + 终点
typedef ChessMove = ({ChessPos from, ChessPos to});

/// 象棋棋盘（可变容器）
/// 选择可变设计的原因：对局页集中持有棋盘状态，走子只需搬运两格，
/// 悔棋用 revertMove 恢复起点棋子与被吃子即可，无需整盘重建
class ChessBoard {
  static const int cols = 9;
  static const int rows = 10;

  /// 90 格紧凑编码中的空格占位符（不与 KABNRCP 大小写冲突）
  static const String _emptyChar = '.';

  ChessBoard._() : _squares = List.filled(cols * rows, null);

  /// 格子存储：index = row * 9 + col
  final List<ChessPiece?> _squares;

  /// 开局标准局面：32 子各就各位（红在下先行，黑在上）
  factory ChessBoard.initial() {
    final board = ChessBoard._();
    // 底线从红方视角左到右：车马象仕帅仕象马车（红黑对称）
    const backRank = [
      ChessPieceType.rook,
      ChessPieceType.knight,
      ChessPieceType.bishop,
      ChessPieceType.advisor,
      ChessPieceType.king,
      ChessPieceType.advisor,
      ChessPieceType.bishop,
      ChessPieceType.knight,
      ChessPieceType.rook,
    ];
    for (var col = 0; col < cols; col++) {
      final type = backRank[col];
      board._squares[col] = ChessPiece(ChessColor.red, type); // row 0
      board._squares[9 * cols + col] = ChessPiece(ChessColor.black, type); // row 9
    }
    // 炮位于底线前两行（col 1 与 col 7），兵/卒位于第三行（逢列布子）
    for (final col in [1, 7]) {
      board._squares[2 * cols + col] = const ChessPiece(ChessColor.red, ChessPieceType.cannon);
      board._squares[7 * cols + col] = const ChessPiece(ChessColor.black, ChessPieceType.cannon);
    }
    for (var col = 0; col < cols; col += 2) {
      board._squares[3 * cols + col] = const ChessPiece(ChessColor.red, ChessPieceType.pawn);
      board._squares[6 * cols + col] = const ChessPiece(ChessColor.black, ChessPieceType.pawn);
    }
    return board;
  }

  bool _inBoard(int col, int row) => col >= 0 && col < cols && row >= 0 && row < rows;

  /// 读取某格棋子（空格返回 null）
  ChessPiece? pieceAt(ChessPos pos) {
    final (col, row) = pos;
    assert(_inBoard(col, row), '坐标越界：$pos');
    return _squares[row * cols + col];
  }

  /// 执行走子：起点棋子搬到终点，返回被吃掉的棋子（无吃子返回 null，悔棋时需回传 revertMove）
  /// 走子是否合法由规则引擎与调用方保证，本方法只做搬运
  ChessPiece? applyMove(ChessMove move) {
    final piece = pieceAt(move.from);
    assert(piece != null, '起点无棋子：${move.from}');
    final captured = pieceAt(move.to);
    _squares[move.to.$2 * cols + move.to.$1] = piece;
    _squares[move.from.$2 * cols + move.from.$1] = null;
    return captured;
  }

  /// 撤销一次 applyMove（本地悔棋用）：棋子搬回起点并恢复被吃子
  void revertMove(ChessMove move, ChessPiece? captured) {
    final piece = pieceAt(move.to);
    assert(piece != null, '终点无棋子：${move.to}');
    _squares[move.from.$2 * cols + move.from.$1] = piece;
    _squares[move.to.$2 * cols + move.to.$1] = captured;
  }

  /// 90 格紧凑编码：每格一个字符（红大写黑小写、空格 '.'），按 row 0 → row 9 顺序拼接
  /// 该格式为存档序列化的底层约定（阶段 4 的存档模型直接复用），定稿后不再变动
  String encode() => _squares.map((p) => p?.code ?? _emptyChar).join();

  /// 从紧凑编码还原棋盘；编码不合法时抛 [FormatException]
  ///
  /// 注意：lib/ 生产路径当前不经过此入口——存档校验走「重放走子 +
  /// encode 对比」（见 ChessStorage/页面恢复逻辑），本方法作为编码的
  /// 逆向工具保留，供测试做结构校验与编解码往返验证
  static ChessBoard decode(String code) {
    if (code.length != cols * rows) {
      throw const FormatException('棋盘编码长度无效');
    }
    final board = ChessBoard._();
    var redCount = 0;
    var blackCount = 0;
    var redKingCount = 0;
    var blackKingCount = 0;
    for (var i = 0; i < code.length; i++) {
      final piece = ChessPiece.fromCode(code[i]);
      if (piece == null && code[i] != _emptyChar) {
        throw const FormatException('棋盘编码含非法字符');
      }
      board._squares[i] = piece;
      if (piece == null) continue;
      switch (piece.color) {
        case ChessColor.red:
          redCount++;
          if (piece.type == ChessPieceType.king) redKingCount++;
        case ChessColor.black:
          blackCount++;
          if (piece.type == ChessPieceType.king) blackKingCount++;
      }
    }
    // 结构性校验：对局中只会吃子不会增子，双方必须各剩一帅/将且不超过初始 16 子
    if (redKingCount != 1 || blackKingCount != 1 || redCount > 16 || blackCount > 16) {
      throw const FormatException('棋盘编码子力结构无效');
    }
    return board;
  }
}
