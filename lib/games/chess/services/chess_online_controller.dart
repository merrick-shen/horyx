import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/models/chess_piece.dart';
import 'package:horyx/games/chess/services/chess_rules.dart';
import 'package:horyx/shared/network/net_message.dart';
import 'package:horyx/shared/network/online_game_controller.dart';
import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/network/room_host.dart';

/// 悔棋协商状态机
/// idle -> awaitingPeer（我发起了请求，等对方应答）
/// idle -> peerRequesting（对方请求悔棋，等我应答）
/// 应答后回到 idle（同意时随广播回退棋盘）
enum UndoState {
  /// 无进行中的悔棋协商
  idle,

  /// 我方已发起请求，等待对方应答
  awaitingPeer,

  /// 对方发起请求，等待我方应答
  peerRequesting,
}

/// 中国象棋联机对局控制器（房主权威模型）
/// 公共骨架（连接持有/挂接/断线终局/生命周期）见基类
/// [OnlineGameControllerBase]，回合制回执能力（回执构造/拒绝文案映射）
/// 来自混入 [SubmissionReceiptMixin]，本类只实现象棋游戏逻辑：
/// 走子校验与广播、将死/困毙判定、悔棋协商、认输。
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
    with SubmissionReceiptMixin {
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
  int? winnerSeat;

  /// 终局原因（将死/困毙/认输）；无胜负时为 null
  ChessEndReason? winReason;

  /// 悔棋协商状态
  UndoState undoState = UndoState.idle;

  /// 同意悔棋后的目标手数（发起方"悔自己上一手"后的长度）
  /// 发起时快照：协商期间对方若又走子，同意后一并回退到快照（B9）
  int _undoTarget = 0;

  /// 当前行棋方颜色（红先，随走子数奇偶推导，避免独立状态失同步）
  ChessColor get turnColor =>
      moves.length.isEven ? ChessColor.red : ChessColor.black;

  /// 当前行棋座位（红=座位 1 起，随走子数奇偶推导）
  int get currentSeat => moves.length.isEven ? 1 : 2;

  /// 我执子的颜色（座位 1 执红）
  ChessColor get myColor =>
      mySeat == 1 ? ChessColor.red : ChessColor.black;

  /// 胜方文案（'红方'/'黑方'）；对局进行中为 null
  String? get winnerText =>
      winnerSeat == null ? null : (winnerSeat == 1 ? '红方' : '黑方');

  /// 是否轮到自己走子（终局后禁止继续）
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

  /// 发起悔棋请求（悔自己上一手）：仅对方回合可发起——轮到自己时
  /// 最后一手是对方的子，悔棋语义不成立（B9）。发起时快照手数，
  /// 同意后回退到快照（协商期间对方新走的子一并回退）。
  /// 房主直接进入协商（本地应答方是客户端），客户端发请求给房主
  void requestUndo() {
    if (winnerSeat != null || gameEndedText != null) return;
    if (moves.isEmpty) {
      onHint?.call('还没有走子，无需悔棋');
      return;
    }
    if (isMyTurn) {
      // 最后一手是对方的子，悔棋只能悔自己的上一手
      onHint?.call('只能在对方回合悔棋（悔自己的上一手）');
      return;
    }
    if (undoState != UndoState.idle) return; // 已有协商进行中
    _undoTarget = moves.length - 1;
    final msg = _msg(NetMessageType.undoRequest, {'count': moves.length});
    final host = this.host;
    if (host != null) {
      undoState = UndoState.awaitingPeer;
      notifyListeners();
      host.sendTo(peerSeat, msg);
    } else {
      // 客户端同样置 awaitingPeer：按钮进入"等待对方应答"防重复发起
      undoState = UndoState.awaitingPeer;
      notifyListeners();
      client?.send(msg);
    }
  }

  /// 应答对方的悔棋请求（仅 peerRequesting 状态有效）
  /// 同意：房主直接回退并广播；客户端发应答给房主仲裁
  void respondUndo(bool accept) {
    if (undoState != UndoState.peerRequesting) return;
    final host = this.host;
    if (host != null) {
      undoState = UndoState.idle;
      if (accept) {
        _revertTo(_undoTarget);
        notifyListeners();
        host.broadcast(
          _msg(NetMessageType.undoApplied, {'target': _undoTarget}),
        );
      } else {
        notifyListeners();
        host.sendTo(
          peerSeat,
          _msg(NetMessageType.undoResponse, {'accept': false}),
        );
      }
    } else {
      undoState = UndoState.idle;
      notifyListeners();
      client?.send(
        _msg(NetMessageType.undoResponse, {'accept': accept}),
      );
    }
  }

  /// 认输：判对方获胜（房主本地生效并广播，客户端声明给房主）
  void resign() {
    if (winnerSeat != null || gameEndedText != null) return;
    final host = this.host;
    if (host != null) {
      winnerSeat = peerSeat;
      winReason = ChessEndReason.resign;
      notifyListeners();
      host.broadcast(
        NetMessage(
          type: NetMessageType.gameOver,
          payload: {'reason': 'resign', 'winner': peerSeat},
        ),
      );
    } else {
      client?.send(_msg(NetMessageType.resign));
    }
  }

  /// 房主收客户端提交：全量校验后生效并广播
  /// （客户端不可信：本地拦截过的规则在房主侧全部重做）
  @override
  void onHostGameMessage(int seat, NetMessage msg) {
    switch (msg.type) {
      case NetMessageType.moveSubmit:
        _onHostMoveSubmit(seat, msg);
      case NetMessageType.undoRequest:
        _onHostUndoRequest(seat, msg);
      case NetMessageType.undoResponse:
        _onHostUndoResponse(seat, msg);
      case NetMessageType.resign:
        _onHostResign(seat);
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
        piece.color != (seat == 1 ? ChessColor.red : ChessColor.black)) {
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

  /// 房主收悔棋请求（仅来自客户端）：本地进入待应答状态（页面弹窗），
  /// 不转发——房主自己就是应答方，本地 respondUndo 处理。
  /// 终极校验载荷 count（发起方快照手数）：数值合法且快照末位确实是
  /// 请求方的子（防"悔对方的子"或篡改），否则忽略请求
  void _onHostUndoRequest(int seat, NetMessage msg) {
    if (winnerSeat != null || gameEndedText != null) return;
    if (undoState != UndoState.idle) return; // 已有协商进行中
    final count = msg.payload['count'];
    if (count is! int || count < 1 || count > moves.length) return;
    // 快照末位（索引 count-1）的执子方须为请求方：偶索引=红=座位1
    if ((count - 1).isEven != (seat == 1)) return;
    _undoTarget = count - 1;
    undoState = UndoState.peerRequesting;
    notifyListeners();
  }

  /// 房主收悔棋应答（客户端应答房主发起的请求）：
  /// 同意则广播回退（双端各自执行），拒绝仅本地提示；状态复位
  void _onHostUndoResponse(int seat, NetMessage msg) {
    if (undoState != UndoState.awaitingPeer) return; // 非我方请求的应答，忽略
    undoState = UndoState.idle;
    final accepted = msg.payload['accept'] == true;
    if (accepted) {
      _revertTo(_undoTarget);
      notifyListeners();
      host?.broadcast(
        _msg(NetMessageType.undoApplied, {'target': _undoTarget}),
      );
    } else {
      onHint?.call('对方拒绝了悔棋请求');
      notifyListeners();
    }
  }

  /// 房主收认输声明：判对方获胜并广播终局
  void _onHostResign(int seat) {
    if (winnerSeat != null || gameEndedText != null) return;
    winnerSeat = peerSeatOf(seat);
    winReason = ChessEndReason.resign;
    notifyListeners();
    host?.broadcast(
      NetMessage(
        type: NetMessageType.gameOver,
        payload: {'reason': 'resign', 'winner': peerSeatOf(seat)},
      ),
    );
  }

  /// 走子生效：搬运棋子 + 入列 + 终局判定；房主侧同步广播
  /// （将死/困毙时携带胜方座位与原因，与本地对局同一 judgeEnd 判定）
  void _applyMove(ChessMove move) {
    board.applyMove(move);
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

  /// 房主侧：对方离开（掉线/主动退出）——对局直接结束，不判胜负
  /// （与单词PK/五子棋一致：中途退出属异常终止，留局方无胜利可言；
  /// 2 人局无人可收到广播，仅本地终局）
  @override
  void onSeatLeft(int seat) {
    if (gameEndedText != null || winnerSeat != null) return;
    endGame(EndGameReason.peerLeft);
    notifyListeners();
  }

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
        board.applyMove(move);
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
      case NetMessageType.undoRequest:
        // 房主转发的悔棋请求：进入待应答状态（页面弹窗）
        undoState = UndoState.peerRequesting;
        notifyListeners();
      case NetMessageType.undoResponse:
        // 我方请求的应答：状态复位；同意/拒绝都不动棋盘，
        // 同意的回退统一以 undoApplied 广播为准（避免与应答双回退）
        undoState = UndoState.idle;
        if (msg.payload['accept'] != true) {
          onHint?.call('对方拒绝了悔棋请求');
        }
        notifyListeners();
      case NetMessageType.undoApplied:
        // 广播回退（target = 发起方快照）：双端同步回退到快照
        // （含协商期间的新走子）。请求方（awaitingPeer，房主本地
        // 同意不经过应答消息）在此一并复位协商状态
        undoState = UndoState.idle;
        final target = msg.payload['target'];
        if (target is int && target >= 0 && target < moves.length) {
          _revertTo(target);
        } else if (moves.isNotEmpty) {
          // target 缺失/非法的兜底：退一手（同版本协议下不会走到）
          _revertTo(moves.length - 1);
        }
        notifyListeners();
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

  /// 构造对局消息的便捷方法（悔棋协商/认输等）
  static NetMessage _msg(
    NetMessageType type, [
    Map<String, dynamic> payload = const {},
  ]) =>
      NetMessage(type: type, payload: payload);

  /// 提交回执的消息类型（象棋为 moveResult）
  @override
  NetMessageType get resultMessageType => NetMessageType.moveResult;
}
