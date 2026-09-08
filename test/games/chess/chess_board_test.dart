import 'package:flutter_test/flutter_test.dart';
import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/models/chess_piece.dart';

/// 阶段 1：棋子与棋盘基础模型单测
/// 验证初始局面、走子搬运/回退与 90 格紧凑编码约定
void main() {
  /// 统计某颜色棋子的类型数量分布
  Map<ChessPieceType, int> countByType(ChessBoard board, ChessColor color) {
    final counts = <ChessPieceType, int>{};
    for (var row = 0; row < ChessBoard.rows; row++) {
      for (var col = 0; col < ChessBoard.cols; col++) {
        final piece = board.pieceAt((col, row));
        if (piece != null && piece.color == color) {
          counts[piece.type] = (counts[piece.type] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  group('初始局面', () {
    test('双方各 16 子，七类棋子数量符合开局规则', () {
      final board = ChessBoard.initial();
      const expected = {
        ChessPieceType.king: 1,
        ChessPieceType.advisor: 2,
        ChessPieceType.bishop: 2,
        ChessPieceType.knight: 2,
        ChessPieceType.rook: 2,
        ChessPieceType.cannon: 2,
        ChessPieceType.pawn: 5,
      };
      expect(countByType(board, ChessColor.red), expected);
      expect(countByType(board, ChessColor.black), expected);
    });

    test('关键棋子位置正确（红在下 row 0，黑在上 row 9）', () {
      final board = ChessBoard.initial();
      expect(board.pieceAt((4, 0)), const ChessPiece(ChessColor.red, ChessPieceType.king));
      expect(board.pieceAt((4, 9)), const ChessPiece(ChessColor.black, ChessPieceType.king));
      expect(board.pieceAt((0, 0)), const ChessPiece(ChessColor.red, ChessPieceType.rook));
      expect(board.pieceAt((1, 2)), const ChessPiece(ChessColor.red, ChessPieceType.cannon));
      expect(board.pieceAt((4, 3)), const ChessPiece(ChessColor.red, ChessPieceType.pawn));
      expect(board.pieceAt((4, 6)), const ChessPiece(ChessColor.black, ChessPieceType.pawn));
      expect(board.pieceAt((1, 7)), const ChessPiece(ChessColor.black, ChessPieceType.cannon));
      // 楚河汉界中线无子
      expect(board.pieceAt((4, 4)), isNull);
      expect(board.pieceAt((4, 5)), isNull);
    });
  });

  group('applyMove 与 revertMove', () {
    test('无吃子走子：起点清空、终点落子、返回 null', () {
      final board = ChessBoard.initial();
      final captured = board.applyMove((from: (0, 0), to: (0, 1)));
      expect(captured, isNull);
      expect(board.pieceAt((0, 0)), isNull);
      expect(board.pieceAt((0, 1)), const ChessPiece(ChessColor.red, ChessPieceType.rook));
    });

    test('吃子走子：返回被吃棋子、终点被替换（仅测搬运语义，合法性归规则引擎）', () {
      final board = ChessBoard.initial();
      final captured = board.applyMove((from: (0, 3), to: (0, 6)));
      expect(captured, const ChessPiece(ChessColor.black, ChessPieceType.pawn));
      expect(board.pieceAt((0, 6)), const ChessPiece(ChessColor.red, ChessPieceType.pawn));
      expect(board.pieceAt((0, 3)), isNull);
    });

    test('走子后回退：棋盘编码还原到走子前', () {
      final board = ChessBoard.initial();
      final before = board.encode();
      final captured = board.applyMove((from: (1, 0), to: (2, 2)));
      expect(board.encode(), isNot(before));
      board.revertMove((from: (1, 0), to: (2, 2)), captured);
      expect(board.encode(), before);
    });

    test('吃子后回退：被吃棋子归位', () {
      final board = ChessBoard.initial();
      final before = board.encode();
      final captured = board.applyMove((from: (0, 3), to: (0, 6)));
      board.revertMove((from: (0, 3), to: (0, 6)), captured);
      expect(board.encode(), before);
      expect(board.pieceAt((0, 6)), const ChessPiece(ChessColor.black, ChessPieceType.pawn));
    });
  });

  group('90 格紧凑编码', () {
    /// 开局局面的定稿编码（row 0 红方底线 → row 9 黑方底线）
    const initialCode = 'RNBAKABNR' // row 0
        '.........' // row 1
        '.C.....C.' // row 2
        'P.P.P.P.P' // row 3
        '.........' // row 4
        '.........' // row 5
        'p.p.p.p.p' // row 6
        '.c.....c.' // row 7
        '.........' // row 8
        'rnbakabnr'; // row 9

    test('初始局面编码与定稿格式一致（90 字符）', () {
      expect(ChessBoard.initial().encode(), initialCode);
    });

    test('编码往返一致：decode 后关键位置与子力分布不变', () {
      final restored = ChessBoard.decode(ChessBoard.initial().encode());
      expect(restored.encode(), initialCode);
      expect(restored.pieceAt((4, 0)), const ChessPiece(ChessColor.red, ChessPieceType.king));
      expect(restored.pieceAt((7, 2)), const ChessPiece(ChessColor.red, ChessPieceType.cannon));
      expect(restored.pieceAt((8, 9)), const ChessPiece(ChessColor.black, ChessPieceType.rook));
    });

    test('对局中途局面（含吃子）往返一致', () {
      final board = ChessBoard.initial();
      board.applyMove((from: (0, 0), to: (0, 6)));
      final restored = ChessBoard.decode(board.encode());
      expect(restored.encode(), board.encode());
      expect(restored.pieceAt((0, 6)), const ChessPiece(ChessColor.red, ChessPieceType.rook));
      expect(restored.pieceAt((0, 0)), isNull);
    });

    test('非法编码抛 FormatException', () {
      // 长度不足
      expect(() => ChessBoard.decode('RNBAKABNR'), throwsFormatException);
      // 含非法字符
      expect(() => ChessBoard.decode('X' * 90), throwsFormatException);
      // 缺红帅
      expect(() => ChessBoard.decode(initialCode.replaceFirst('K', '.')), throwsFormatException);
      // 红方子力超上限（空格填入红车）
      expect(() => ChessBoard.decode(initialCode.replaceFirst('.', 'R')), throwsFormatException);
      // 双红帅
      expect(() => ChessBoard.decode(initialCode.replaceFirst('R', 'K')), throwsFormatException);
    });
  });
}
