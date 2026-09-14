import 'package:horyx/shared/network/board_game_online_controller.dart';
import 'package:horyx/shared/network/net_message.dart';
import 'package:horyx/shared/network/online_game_controller.dart';
import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/network/room_host.dart';
import 'package:horyx/shared/network/undo_resign_negotiation.dart';
import 'package:horyx/games/gomoku/services/gomoku_rules.dart';

/// 五子棋联机对局控制器（房主权威模型）
/// 公共骨架（连接持有/挂接/断线终局/生命周期）见基类
/// [OnlineGameControllerBase]，回合制回执能力（回执构造/拒绝文案映射）
/// 来自混入 [SubmissionReceiptMixin]；悔棋/认输协商全流程（请求/应答/
/// 房主仲裁/认输/2 人局对方离开终局）来自混入 [UndoResignNegotiationMixin]
/// （棋类通用，唯一实现），本类只实现五子棋游戏逻辑与协商钩子：
/// 落子校验与广播、五连判定、悔棋回退（removeRange）、执子归属校验。
/// 房主端：校验落子（轮次 + 落点）并广播生效，五连时判定胜负；
/// 客户端：提交落子交房主校验，棋盘状态随广播同步，不自行判定合法性
/// （仅对广播做最低一致性校验：落点在盘内且未重复，矛盾即终局）。
/// 执子规则固定：创建者（座位 1）执黑先行，加入者（座位 2）执白。
/// 悔棋为双方协商：请求 -> 对方应答 -> 房主广播回退，全程房主仲裁；
/// 认输为单方声明：房主收到即判对方获胜并广播终局；
/// 中途退出（任一方）对局直接结束，不判胜负（与单词PK一致）。
class GomokuOnlineController extends OnlineGameControllerBase
    with SubmissionReceiptMixin, UndoResignNegotiationMixin
    implements BoardGameOnlineController {
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
  @override
  int? winnerSeat;

  /// 胜负是否来自认输（终局弹窗文案区分）
  bool wonByResign = false;

  /// 当前执子座位（黑=1 起，随落子数奇偶推导）
  int get currentSeat => moves.length.isEven ? 1 : 2;

  /// 胜方文案（'黑方'/'白方'）；对局进行中为 null
  @override
  String? get winnerText =>
      winnerSeat == null ? null : (winnerSeat == 1 ? '黑方' : '白方');

  /// 是否轮到自己落子（终局后禁止继续）
  @override
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

  // ---- 悔棋/认输协商钩子实现（全流程见 UndoResignNegotiationMixin）----

  /// 已生效手数（悔棋快照基准）
  @override
  int get moveCount => moves.length;

  /// 第 [moveIndex] 手（0 基）是否为 [seat] 方所下：
  /// 偶索引=黑=座位1、奇索引=白=座位2
  @override
  bool isMoveBy(int moveIndex, int seat) =>
      seat == 1 ? moveIndex.isEven : moveIndex.isOdd;

  /// 执行悔棋回退：撤到快照手数（含协商期间的新落子），
  /// 仅由房主侧在广播前调用
  @override
  void applyUndoRollback(int target) {
    if (target < moves.length) {
      moves.removeRange(target, moves.length);
    }
  }

  /// 认输生效：[winner] 获胜（终局弹窗文案区分认输）
  @override
  void declareResignWinner(int winner) {
    winnerSeat = winner;
    wonByResign = true;
  }

  /// 尚无落子可悔的提示文案
  @override
  String get noMoveHintText => '还没有落子，无需悔棋';

  /// 房主收客户端提交：校验轮次与落点，拒绝单独回执提交者，通过则广播生效
  /// （客户端不可信：本地拦截过的规则在房主侧全部重做）
  @override
  void onHostGameMessage(int seat, NetMessage msg) {
    switch (msg.type) {
      case NetMessageType.stoneSubmit:
        _onHostStoneSubmit(seat, msg);
      case NetMessageType.undoRequest ||
          NetMessageType.undoResponse ||
          NetMessageType.resign:
        handleHostUndoResignMessage(seat, msg);
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

  /// 房主侧：对方离开（掉线/主动退出）的 2 人局终局语义
  /// 由 [UndoResignNegotiationMixin.onSeatLeft] 统一实现

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
        return '还没轮到你落子';
      case 'occupied':
        return '此处已有棋子';
      default:
        return '落子未被接受，请重试';
    }
  }

  /// 提交回执的消息类型（五子棋为 stoneResult）
  @override
  NetMessageType get resultMessageType => NetMessageType.stoneResult;
}
