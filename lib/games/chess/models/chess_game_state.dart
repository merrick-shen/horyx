import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/models/chess_piece.dart';
import 'package:horyx/shared/storage/archive_storage.dart';

/// 象棋未完成对局的存档状态
/// 用于「保存并退出」时持久化，下次进入应用可恢复对局
class ChessGameState implements GameArchiveSummary {
  const ChessGameState({
    required this.boardCode,
    required this.turn,
    required this.moves,
    required this.savedAt,
  });

  /// 当前局面的 90 格紧凑编码（ChessBoard.encode 产出，恢复即还原全部子力）
  final String boardCode;

  /// 当前轮次（红先黑后交替）
  final ChessColor turn;

  /// 已走着法序列（本地悔棋回退与棋谱展示使用）
  final List<ChessMove> moves;

  /// 存档时间
  @override
  final DateTime savedAt;


  /// 数据格式版本号：字段结构变更时递增，便于后续读取旧档时迁移
  static const int version = 1;

  Map<String, dynamic> toJson() => {
        'version': version,
        'board': boardCode,
        // ChessColor 枚举以 red/black 字符串持久化，避免索引值与枚举顺序耦合
        'turn': turn == ChessColor.red ? 'red' : 'black',
        // record 无法直接序列化，压缩为 [fromCol, fromRow, toCol, toRow] 四元数组
        'moves': [
          for (final m in moves) [m.from.$1, m.from.$2, m.to.$1, m.to.$2],
        ],
        'savedAt': savedAt.toIso8601String(),
      };

  /// 反序列化；数据缺失或格式不符时抛出 [FormatException]，由上层容错处理
  factory ChessGameState.fromJson(Map<String, dynamic> json) {
    final boardCode = json['board'];
    if (boardCode is! String || boardCode.length != 90) {
      throw const FormatException('存档 board 字段无效');
    }
    final turnCode = json['turn'];
    if (turnCode is! String || (turnCode != 'red' && turnCode != 'black')) {
      throw const FormatException('存档 turn 字段无效');
    }
    final moveList = json['moves'];
    if (moveList is! List) {
      throw const FormatException('存档 moves 字段无效');
    }
    final moves = <ChessMove>[];
    for (final m in moveList) {
      if (m is! List || m.length != 4) {
        throw const FormatException('存档 moves 条目无效');
      }
      moves.add((
        from: (m[0] as int, m[1] as int),
        to: (m[2] as int, m[3] as int),
      ));
    }
    return ChessGameState(
      boardCode: boardCode,
      turn: turnCode == 'red' ? ChessColor.red : ChessColor.black,
      moves: moves,
      savedAt: DateTime.parse(json['savedAt'] as String),
    );
  }
}
