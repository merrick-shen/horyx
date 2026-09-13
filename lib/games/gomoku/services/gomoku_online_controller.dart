import 'package:horyx/shared/network/net_message.dart';
import 'package:horyx/shared/network/online_game_controller.dart';
import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/network/room_host.dart';
import 'package:horyx/games/gomoku/services/gomoku_rules.dart';

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

/// 五子棋联机对局控制器（房主权威模型）
/// 公共骨架（连接持有/挂接/断线终局/生命周期）见基类
/// [OnlineGameControllerBase]，回合制回执能力（回执构造/拒绝文案映射）
/// 来自混入 [SubmissionReceiptMixin]，本类只实现五子棋游戏逻辑：
/// 落子校验与广播、五连判定、悔棋协商、认输。
/// 房主端：校验落子（轮次 + 落点）并广播生效，五连时判定胜负；
/// 客户端：提交落子交房主校验，棋盘状态随广播同步，不自行判定合法性
/// （仅对广播做最低一致性校验：落点在盘内且未重复，矛盾即终局）。
/// 执子规则固定：创建者（座位 1）执黑先行，加入者（座位 2）执白。
/// 悔棋为双方协商：请求 -> 对方应答 -> 房主广播回退，全程房主仲裁；
/// 认输为单方声明：房主收到即判对方获胜并广播终局；
/// 中途退出（任一方）对局直接结束，不判胜负（与单词PK一致）。
class GomokuOnlineController extends OnlineGameControllerBase
    with SubmissionReceiptMixin {
  /// 以房主身份接管房间（满员开局后由等待页调用）
  /// [boardSize] 为建房时所选棋盘规格，随 gameStart 已广播给客户端
  factory GomokuOnlineController.host(RoomHost host, {required int boardSize}) {
    return GomokuOnlineController._(
      host: host,
      boardSize: boardSize,
      mySeat: 1,
    )..initialize();
  }

  /// 以客户端身份接管房间（收到 gameStart 后由等待页调用）
  /// 棋盘规格从开局载荷读取（房主建房所选）；规格缺失或非法时
  /// 直接终止对局——静默回退 15 路会导致双端棋盘不一致（B12），
  /// 正常同版本协议下不会发生，此处防御协议演进/载荷异常
  factory GomokuOnlineController.client(RoomClient client) {
    final raw = client.startPayload['boardSize'];
    final valid = raw is int && (raw == 15 || raw == 19);
    final controller = GomokuOnlineController._(
      client: client,
      // 非法时兜底 15 仅用于终局弹窗前的空棋盘渲染
      boardSize: valid ? raw : 15,
      mySeat: client.mySeat ?? 2,
    )..initialize();
    if (!valid) {
      controller.endGame(EndGameReason.dataError);
    }
    return controller;
  }

  GomokuOnlineController._({
    super.host,
    super.client,
    required this.boardSize,
    required super.mySeat,
  });

  /// 棋盘路数（15/19，由房主建房时选定）
  final int boardSize;

  /// 已生效落子序列（索引奇偶决定黑白：偶=黑=座位1，奇=白=座位2）
  final List<(int, int)> moves = [];

  /// 胜方座位号；null 表示对局进行中或异常终止（无胜负）
  int? winnerSeat;

  /// 胜负是否来自认输（终局弹窗文案区分）
  bool wonByResign = false;

  /// 悔棋协商状态
  UndoState undoState = UndoState.idle;

  /// 同意悔棋后的目标手数（发起方"悔自己上一手"后的长度）
  /// 发起时快照：协商期间对方若又落子，同意后一并回退到快照（B9）
  int _undoTarget = 0;

  /// 当前执子座位（黑=1 起，随落子数奇偶推导）
  int get currentSeat => moves.length.isEven ? 1 : 2;

  /// 胜方文案（'黑方'/'白方'）；对局进行中为 null
  String? get winnerText =>
      winnerSeat == null ? null : (winnerSeat == 1 ? '黑方' : '白方');

  /// 是否轮到自己落子（终局后禁止继续）
  bool get isMyTurn =>
      currentSeat == mySeat && winnerSeat == null && gameEndedText == null;

  /// 我执黑（座位 1）？
  bool get isBlack => mySeat == 1;

  /// 提交落子（页面点击棋盘交叉点后调用）
  /// 本地先拦一层明显非法的提交（省一次网络往返），
  /// 真实性仍由房主最终裁决；返回 true 表示已受理（房主模式即生效）
  bool submitStone(int col, int row) {
    if (winnerSeat != null || gameEndedText != null) return false;
    if (currentSeat != mySeat) {
      onHint?.call('还没轮到你落子');
      return false;
    }
    if (_occupied(col, row)) {
      onHint?.call('此处已有棋子');
      return false;
    }
    if (host != null) {
      _applyStone(col, row);
      return true;
    }
    client?.send(
      NetMessage(
        type: NetMessageType.stoneSubmit,
        payload: {'col': col, 'row': row},
      ),
    );
    return true;
  }

  /// 落点是否已有棋子
  bool _occupied(int col, int row) =>
      moves.any((m) => m.$1 == col && m.$2 == row);

  /// 执行悔棋回退：撤到发起方快照（_undoTarget），
  /// 含协商期间快照之后的新落子；仅由房主侧在广播前调用
  void _applyUndo() {
    if (_undoTarget < moves.length) {
      moves.removeRange(_undoTarget, moves.length);
    }
  }

  /// 发起悔棋请求（悔自己上一手）：仅对方回合可发起——轮到自己时
  /// 最后一手是对方的子，悔棋语义不成立（B9）。发起时快照手数，
  /// 同意后回退到快照（协商期间对方新落的子一并回退）。
  /// 房主直接进入协商（本地应答方是客户端），客户端发请求给房主
  void requestUndo() {
    if (winnerSeat != null || gameEndedText != null) return;
    if (moves.isEmpty) {
      onHint?.call('还没有落子，无需悔棋');
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
        _applyUndo();
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
      // 对方获胜：peerSeat 与 _onHostResign 的 peerSeatOf(seat) 同一规则
      winnerSeat = peerSeat;
      wonByResign = true;
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

  /// 房主收客户端提交：校验轮次与落点，拒绝单独回执提交者，通过则广播生效
  /// （客户端不可信：本地拦截过的规则在房主侧全部重做）
  @override
  void onHostGameMessage(int seat, NetMessage msg) {
    switch (msg.type) {
      case NetMessageType.stoneSubmit:
        _onHostStoneSubmit(seat, msg);
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

  /// 房主收落子提交：校验轮次与落点
  void _onHostStoneSubmit(int seat, NetMessage msg) {
    if (winnerSeat != null) return; // 对局已结束，忽略迟到的提交
    final col = msg.payload['col'];
    final row = msg.payload['row'];
    if (col is! int || row is! int) return;
    if (seat != currentSeat) {
      host?.sendTo(seat, resultMessage(false, 'notYourTurn'));
      return;
    }
    if (_occupied(col, row)) {
      host?.sendTo(seat, resultMessage(false, 'occupied'));
      return;
    }
    host?.sendTo(seat, resultMessage(true, null));
    _applyStone(col, row);
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
    // 快照末位（索引 count-1）的颜色须为请求方：偶索引=黑=座位1
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
      _applyUndo();
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
    wonByResign = true;
    notifyListeners();
    host?.broadcast(
      NetMessage(
        type: NetMessageType.gameOver,
        payload: {'reason': 'resign', 'winner': peerSeatOf(seat)},
      ),
    );
  }

  /// 落子生效：入列 + 五连判定；房主侧同步广播（五连时携带胜方座位）
  void _applyStone(int col, int row) {
    moves.add((col, row));
    if (GomokuRules.hasFiveInRow(
      moves,
      boardSize,
      col,
      row,
      moves.length.isOdd,
    )) {
      // 刚落的子颜色 = 序列长度奇偶（1 手黑、2 手白……）
      winnerSeat = moves.length.isOdd ? 1 : 2;
    }
    notifyListeners();
    host?.broadcast(
      NetMessage(
        type: NetMessageType.stoneApplied,
        payload: {
          'col': col,
          'row': row,
          'player': moves.length.isOdd ? 1 : 2,
          if (winnerSeat != null) 'winner': winnerSeat,
        },
      ),
    );
  }

  /// 房主侧：对方离开（掉线/主动退出）——对局直接结束，不判胜负
  /// （与单词PK一致：中途退出属异常终止，留局方无胜利可言；
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
      case NetMessageType.stoneApplied:
        final col = msg.payload['col'];
        final row = msg.payload['row'];
        if (col is! int || row is! int) return;
        // 客户端对房主广播的最低一致性校验（与象棋 moveApplied 对齐）：
        // 落点须在盘内且未被占用。矛盾广播（房主侧异常/协议演进）说明
        // 棋盘已不可信且无重同步手段，走 dataError 终局而非静默应用
        // 污染落子序列（回合奇偶推导、执子卡、渲染全部失真）
        if (col < 0 ||
            col >= boardSize ||
            row < 0 ||
            row >= boardSize ||
            _occupied(col, row)) {
          endGame(EndGameReason.dataError);
          notifyListeners();
          return;
        }
        moves.add((col, row));
        winnerSeat = msg.payload['winner'] as int?;
        notifyListeners();
      case NetMessageType.stoneResult:
        // 拒绝才提示；通过无需处理（生效以 stoneApplied 广播为准）
        if (msg.payload['ok'] != true) {
          onHint?.call(reasonText(msg.payload['reason']));
        }
      case NetMessageType.gameOver:
        winnerSeat = msg.payload['winner'] as int?;
        wonByResign = msg.payload['reason'] == 'resign';
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
        // 广播回退（target = 发起方快照）：双端同步 removeRange 撤到
        // 快照（含协商期间的新落子）。请求方（awaitingPeer，房主本地
        // 同意不经过应答消息）在此一并复位协商状态
        undoState = UndoState.idle;
        final target = msg.payload['target'];
        if (target is int && target >= 0 && target < moves.length) {
          moves.removeRange(target, moves.length);
        } else if (moves.isNotEmpty) {
          // target 缺失/非法的兜底：退一手（同版本协议下不会走到）
          moves.removeLast();
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
        return '还没轮到你落子';
      case 'occupied':
        return '此处已有棋子';
      default:
        return '落子未被接受，请重试';
    }
  }

  /// 构造对局消息的便捷方法（悔棋协商/认输等）
  static NetMessage _msg(
    NetMessageType type, [
    Map<String, dynamic> payload = const {},
  ]) =>
      NetMessage(type: type, payload: payload);

  /// 提交回执的消息类型（五子棋为 stoneResult）
  @override
  NetMessageType get resultMessageType => NetMessageType.stoneResult;
}
