import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/models/chess_piece.dart';
import 'package:horyx/games/chess/services/chess_rules.dart';
import 'package:horyx/shared/network/board_game_online_controller.dart';
import 'package:horyx/shared/network/net_message.dart';
import 'package:horyx/shared/network/online_game_controller.dart';
import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/network/room_host.dart';
import 'package:horyx/shared/network/undo_resign_negotiation.dart';

/// 中国象棋联机对局控制器（房主权威模型）
/// 公共骨架（连接持有/挂接/断线终局/生命周期）见基类
/// [OnlineGameControllerBase]，回合制回执能力（回执构造/拒绝文案映射）
/// 来自混入 [SubmissionReceiptMixin]；悔棋/认输协商全流程（请求/应答/
/// 房主仲裁/认输/2 人局对方离开终局）来自混入 [UndoResignNegotiationMixin]
/// （棋类通用，唯一实现），本类只实现象棋游戏逻辑与协商钩子：
/// 走子校验与广播、将死/困毙判定、悔棋回退（重放重建）、执子归属校验。
/// 房主端：全量校验走子（轮次 + 起点己方棋子 + 合法着法 + 坐标边界）并广播，
/// 走子后用与本地对局同一规则引擎判定将死/困毙；
/// 客户端：提交走子交房主校验，棋盘状态随广播同步，不自行判定合法性
/// （仅对广播做最低一致性校验：起点有子且轮次匹配，矛盾即终局）。
/// 执子规则固定：创建者（座位 1）执红先行，加入者（座位 2）执黑。
/// 悔棋为双方协商：只能悔自己的上一手，轮到对方走子时才可发起（与五子棋
/// 规则一致，避免历史坑），全程房主仲裁；
/// 认输为单方声明：房主收到即判对方获胜并广播终局；
/// 中途退出（任一方）对局直接结束，不判胜负（与单词PK/五子棋一致）。
class ChessOnlineController extends OnlineGameControllerBase
    with SubmissionReceiptMixin, UndoResignNegotiationMixin
    implements BoardGameOnlineController {
  /// 以房主身份接管房间（满员开局后由等待页调用）
  /// 象棋无规格选项，gameStartPayload 为空对象，无需参数
  factory ChessOnlineController.host(RoomHost host) {
    return ChessOnlineController._(host: host, mySeat: 1)..initialize();
  }

  /// 以客户端身份接管房间（收到 gameStart 后由等待页调用）
  /// 开局载荷为空对象（象棋无规格选项），无需校验（无 B12 类参数）
  factory ChessOnlineController.client(RoomClient client) {
    return ChessOnlineController._(
      client: client,
      mySeat: client.mySeat ?? 2,
    )..initialize();
  }

  ChessOnlineController._({super.host, super.client, required super.mySeat});

  /// 对局棋盘（可变容器，与本地对局页同源；
  /// 悔棋回退时从初始局面重放整体重建，故不可 final）
  ChessBoard board = ChessBoard.initial();

  /// 已生效走子序列（索引偶=红=座位1、奇=黑=座位2；悔棋快照回退用）
  final List<ChessMove> moves = [];

  /// 胜方座位号；null 表示对局进行中或异常终止（无胜负）
  @override
  int? winnerSeat;

  /// 最近一步被吃的棋子（走子动画展示用；无吃子为 null）：
  /// 房主侧在走子生效时记录，客户端随 moveApplied 广播生效时记录
  ChessPiece? lastCapturedPiece;

  /// 终局原因（将死/困毙/认输）；无胜负时为 null
  ChessEndReason? winReason;

  // ---- 座位/手数 → 执子颜色映射（单点维护，勿内联展开）----

  /// 座位 → 执子颜色：座位 1（房主）执红、座位 2（客户端）执黑
  static ChessColor colorOfSeat(int seat) =>
      seat == 1 ? ChessColor.red : ChessColor.black;

  /// 第 [index] 手（0 基）的执子颜色：红先，随奇偶推导
  static ChessColor colorOfMoveIndex(int index) =>
      index.isEven ? ChessColor.red : ChessColor.black;

  /// 当前行棋方颜色（红先，随走子数奇偶推导，避免独立状态失同步）
  ChessColor get turnColor => colorOfMoveIndex(moves.length);

  /// 当前行棋座位（红=座位 1 起，随走子数奇偶推导）
  int get currentSeat => moves.length.isEven ? 1 : 2;

  /// 我执子的颜色（座位 1 执红）
  ChessColor get myColor => colorOfSeat(mySeat);

  /// 胜方文案（'红方'/'黑方'）；对局进行中为 null
  @override
  String? get winnerText =>
      winnerSeat == null ? null : (winnerSeat == 1 ? '红方' : '黑方');

  /// 是否轮到自己走子（终局后禁止继续）
  @override
  bool get isMyTurn =>
      turnColor == myColor && winnerSeat == null && gameEndedText == null;

  /// 提交走子（页面确认落子后调用）
  /// 本地先拦一层明显非法的提交（省一次网络往返），
  /// 真实性仍由房主最终裁决；返回 true 表示已受理（房主模式即生效）
  bool submitMove(ChessMove move) {
    if (winnerSeat != null || gameEndedText != null) return false;
    if (turnColor != myColor) {
      onHint?.call('还没轮到你走子');
      return false;
    }
    if (!_isOwnLegalMove(move)) {
      onHint?.call('这不是合法走法');
      return false;
    }
    final host = this.host;
    if (host != null) {
      _applyMove(move);
      return true;
    }
    client?.send(
      NetMessage(
        type: NetMessageType.moveSubmit,
        payload: {
          'fromCol': move.from.$1,
          'fromRow': move.from.$2,
          'toCol': move.to.$1,
          'toRow': move.to.$2,
        },
      ),
    );
    return true;
  }

  /// [move] 是否为「己方棋子的合法着法」：起点须有己方棋子
  /// （起点无子时 legalMovesFor 会断言失败，必须先判），且属于其合法着法集
  bool _isOwnLegalMove(ChessMove move) {
    final piece = board.pieceAt(move.from);
    if (piece == null || piece.color != turnColor) return false;
    return ChessRules.legalMovesFor(board, move.from).contains(move);
  }

  // ---- 悔棋/认输协商钩子实现（全流程见 UndoResignNegotiationMixin）----

  /// 已生效手数（悔棋快照基准）
  @override
  int get moveCount => moves.length;

  /// 第 [moveIndex] 手（0 基）是否为 [seat] 方所下：随奇偶推导执子颜色
  @override
  bool isMoveBy(int moveIndex, int seat) =>
      colorOfMoveIndex(moveIndex) == colorOfSeat(seat);

  /// 执行悔棋回退：从初始局面重放重建（见 [_revertTo]），
  /// 仅由房主侧在广播前调用
  @override
  void applyUndoRollback(int target) => _revertTo(target);

  /// 认输生效：[winner] 获胜（终局弹窗文案区分认输）
  @override
  void declareResignWinner(int winner) {
    winnerSeat = winner;
    winReason = ChessEndReason.resign;
  }

  /// 尚无走子可悔的提示文案
  @override
  String get noMoveHintText => '还没有走子，无需悔棋';

  /// 房主收客户端提交：全量校验后生效并广播
  /// （客户端不可信：本地拦截过的规则在房主侧全部重做）
  @override
  void onHostGameMessage(int seat, NetMessage msg) {
    switch (msg.type) {
      case NetMessageType.moveSubmit:
        _onHostMoveSubmit(seat, msg);
      case NetMessageType.undoRequest ||
          NetMessageType.undoResponse ||
          NetMessageType.resign:
        handleHostUndoResignMessage(seat, msg);
      default:
        break;
    }
  }

  /// 房主收走子提交：坐标边界 -> 轮次 -> 起点己方棋子 -> 合法着法，逐层拒绝
  void _onHostMoveSubmit(int seat, NetMessage msg) {
    if (winnerSeat != null || gameEndedText != null) {
      return; // 对局已结束，忽略迟到的提交
    }
    final move = _moveFromPayload(msg.payload);
    if (move == null) return; // 字段缺失/类型错误/坐标越界，静默丢弃
    if (seat != currentSeat) {
      host?.sendTo(seat, resultMessage(false, 'notYourTurn'));
      return;
    }
    // 起点棋子须为提交方执子颜色（防止「替对方走子」或以空格/敌子为起点）
    final piece = board.pieceAt(move.from);
    if (piece == null ||
        piece.color != colorOfSeat(seat)) {
      host?.sendTo(seat, resultMessage(false, 'invalidMove'));
      return;
    }
    if (!ChessRules.legalMovesFor(board, move.from).contains(move)) {
      // 含蹩马腿/塞象眼/送将等全部规则拒绝：与本地对局同一规则引擎裁决
      host?.sendTo(seat, resultMessage(false, 'invalidMove'));
      return;
    }
    host?.sendTo(seat, resultMessage(true, null));
    _applyMove(move);
  }

  /// 走子生效：搬运棋子 + 入列 + 终局判定；房主侧同步广播
  /// （将死/困毙时携带胜方座位与原因，与本地对局同一 judgeEnd 判定）
  void _applyMove(ChessMove move) {
    lastCapturedPiece = board.applyMove(move);
    moves.add(move);
    // 走子后轮到对方：judgeEnd 判对方是否无路可走（将死/困毙判负，
    // 胜方即刚走子的一方 = 当前序列末手执子方）
    winReason = ChessRules.judgeEnd(board, turnColor);
    if (winReason != null) {
      winnerSeat = moves.length.isOdd ? 1 : 2;
    }
    notifyListeners();
    host?.broadcast(
      NetMessage(
        type: NetMessageType.moveApplied,
        payload: {
          'fromCol': move.from.$1,
          'fromRow': move.from.$2,
          'toCol': move.to.$1,
          'toRow': move.to.$2,
          if (winnerSeat != null) 'winner': winnerSeat,
          if (winReason != null) 'reason': winReason!.name,
        },
      ),
    );
  }

  /// 回退到快照手数：从初始局面正向重放走子序列整体重建棋盘
  /// （逐手 revert 需要被吃子记录，重放让被吃子随重放自然复原，
  /// 且不依赖任何额外状态，悔棋协商双方执行同一确定性过程）
  void _revertTo(int target) {
    if (target < moves.length) {
      final rebuilt = ChessBoard.initial();
      for (var i = 0; i < target; i++) {
        rebuilt.applyMove(moves[i]);
      }
      board = rebuilt;
      moves.removeRange(target, moves.length);
    }
  }

  /// 房主侧：对方离开（掉线/主动退出）的 2 人局终局语义
  /// 由 [UndoResignNegotiationMixin.onSeatLeft] 统一实现

  /// 客户端侧：处理房主对局消息，棋盘状态以广播为准
  @override
  void onClientGameMessage(NetMessage msg) {
    switch (msg.type) {
      case NetMessageType.moveApplied:
        final move = _moveFromPayload(msg.payload);
        if (move == null) return;
        // 客户端对房主广播的最低一致性校验：起点须有棋子且为当前
        // 行棋方棋子（即轮次匹配）。applyMove 是纯搬运无规则校验，
        // 矛盾广播（房主侧异常/协议演进）若直接应用，release 下会
        // 静默破坏局面且无重同步手段——此时棋盘已不可信，终局处理
        final piece = board.pieceAt(move.from);
        if (piece == null || piece.color != turnColor) {
          endGame(EndGameReason.dataError);
          notifyListeners();
          return;
        }
        lastCapturedPiece = board.applyMove(move);
        moves.add(move);
        winnerSeat = msg.payload['winner'] as int?;
        final reasonName = msg.payload['reason'];
        winReason =
            reasonName is String ? ChessEndReason.values.asNameMap()[reasonName] : null;
        notifyListeners();
      case NetMessageType.moveResult:
        // 拒绝才提示；通过无需处理（生效以 moveApplied 广播为准）
        if (msg.payload['ok'] != true) {
          onHint?.call(reasonText(msg.payload['reason']));
        }
      case NetMessageType.gameOver:
        winnerSeat = msg.payload['winner'] as int?;
        winReason = msg.payload['reason'] == 'resign'
            ? ChessEndReason.resign
            : null;
        notifyListeners();
      case NetMessageType.undoRequest ||
          NetMessageType.undoResponse ||
          NetMessageType.undoApplied:
        handleClientUndoMessage(msg);
      default:
        break;
    }
  }

  /// 房主拒绝原因 -> 用户可读文案
  @override
  String reasonText(Object? reason) {
    switch (reason) {
      case 'notYourTurn':
        return '还没轮到你走子';
      case 'invalidMove':
        return '这不是合法走法';
      default:
        return '走子未被接受，请重试';
    }
  }

  /// 从载荷解析走子（字段缺失/类型错误/坐标越界返回 null）：
  /// 越界坐标若流入棋盘搬运会触发越界异常，必须在解析层拦截
  ChessMove? _moveFromPayload(Map<String, dynamic> payload) {
    bool inBoard(int col, int row) =>
        col >= 0 && col < ChessBoard.cols && row >= 0 && row < ChessBoard.rows;
    final fromCol = payload['fromCol'];
    final fromRow = payload['fromRow'];
    final toCol = payload['toCol'];
    final toRow = payload['toRow'];
    if (fromCol is! int ||
        fromRow is! int ||
        toCol is! int ||
        toRow is! int) {
      return null;
    }
    if (!inBoard(fromCol, fromRow) || !inBoard(toCol, toRow)) return null;
    return (
      from: (fromCol, fromRow),
      to: (toCol, toRow),
    );
  }

  /// 提交回执的消息类型（象棋为 moveResult）
  @override
  NetMessageType get resultMessageType => NetMessageType.moveResult;
}
