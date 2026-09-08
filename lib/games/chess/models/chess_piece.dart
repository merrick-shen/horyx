// 象棋棋子模型（纯数据，无 UI 依赖）
// 编码字符沿用 Xiangqi FEN 惯例：KABNRCP 七类，红方大写、黑方小写

/// 棋子颜色：红方先行，黑方后行
enum ChessColor { red, black }

/// 棋子类型（七类），命名与棋规术语对齐
enum ChessPieceType {
  king, // 帅 / 将
  advisor, // 仕 / 士
  bishop, // 相 / 象
  knight, // 马（红黑同字）
  rook, // 车（红黑同字）
  cannon, // 炮（红黑同字）
  pawn; // 兵 / 卒

  /// 90 格紧凑编码使用的字符（红大写黑小写，详见 ChessBoard.encode）
  String codeChar(ChessColor color) => switch (this) {
        ChessPieceType.king => color == ChessColor.red ? 'K' : 'k',
        ChessPieceType.advisor => color == ChessColor.red ? 'A' : 'a',
        ChessPieceType.bishop => color == ChessColor.red ? 'B' : 'b',
        ChessPieceType.knight => color == ChessColor.red ? 'N' : 'n',
        ChessPieceType.rook => color == ChessColor.red ? 'R' : 'r',
        ChessPieceType.cannon => color == ChessColor.red ? 'C' : 'c',
        ChessPieceType.pawn => color == ChessColor.red ? 'P' : 'p',
      };

  /// 棋子面上的汉字（红黑用字不同：帅/将、仕/士、相/象、兵/卒）
  String labelOf(ChessColor color) => switch (this) {
        ChessPieceType.king => color == ChessColor.red ? '帅' : '将',
        ChessPieceType.advisor => color == ChessColor.red ? '仕' : '士',
        ChessPieceType.bishop => color == ChessColor.red ? '相' : '象',
        ChessPieceType.knight => '马',
        ChessPieceType.rook => '车',
        ChessPieceType.cannon => '炮',
        ChessPieceType.pawn => color == ChessColor.red ? '兵' : '卒',
      };
}

/// 一枚棋子 = 颜色 + 类型（不可变值对象，棋盘比较与存档编码都依赖相等性）
class ChessPiece {
  const ChessPiece(this.color, this.type);

  final ChessColor color;
  final ChessPieceType type;

  /// 紧凑编码字符，如红车 'R'、黑卒 'p'
  String get code => type.codeChar(color);

  /// 棋子面上的汉字，如「帅」「卒」
  String get label => type.labelOf(color);

  /// 从编码字符还原棋子；非法字符返回 null（交由调用方决定如何容错）
  static ChessPiece? fromCode(String c) {
    for (final type in ChessPieceType.values) {
      for (final color in ChessColor.values) {
        if (type.codeChar(color) == c) return ChessPiece(color, type);
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ChessPiece && other.color == color && other.type == type;

  @override
  int get hashCode => Object.hash(color, type);
}
