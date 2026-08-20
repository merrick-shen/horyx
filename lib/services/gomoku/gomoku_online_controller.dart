import 'package:flutter/foundation.dart';

import '../../models/net_message.dart';
import '../network/room_client.dart';
import '../network/room_host.dart';

/// 五子棋联机对局控制器（房主权威模型）
/// 房主端：校验落子（轮次 + 落点）并广播生效，五连/对方离开时判定终局；
/// 客户端：提交落子交房主校验，棋盘状态随广播同步，不自行判定。
/// 执子规则固定：创建者（座位 1）执黑先行，加入者（座位 2）执白。
/// 页面销毁（dispose）即退出对局：控制器负责关闭底层房间连接。
/// 悔棋/认输/再来一局协商为后续步骤，本控制器只覆盖落子与终局主干。
class GomokuOnlineController extends ChangeNotifier {
  /// 以房主身份接管房间（满员开局后由等待页调用）
  /// [boardSize] 为建房时所选棋盘规格，随 gameStart 已广播给客户端
  factory GomokuOnlineController.host(RoomHost host, {required int boardSize}) {
    return GomokuOnlineController._(
      host: host,
      client: null,
      boardSize: boardSize,
      mySeat: 1,
    ).._attachHost(host);
  }

  /// 以客户端身份接管房间（收到 gameStart 后由等待页调用）
  /// 棋盘规格从开局载荷读取（房主建房所选），缺失时回退标准 15 路
  factory GomokuOnlineController.client(RoomClient client) {
    return GomokuOnlineController._(
      host: null,
      client: client,
      boardSize: (client.startPayload['boardSize'] as int?) ?? 15,
      mySeat: client.mySeat ?? 2,
    ).._attachClient(client);
  }

  GomokuOnlineController._({
    required this._host,
    required this._client,
    required this.boardSize,
    required this.mySeat,
  });

  /// 房主模式挂接：对局消息与玩家离开回调
  void _attachHost(RoomHost host) {
    host.onGameMessage = _onHostGameMessage;
    host.onSeatLeft = _onSeatLeft;
  }

  /// 客户端模式挂接：对局消息处理（含暂存消息回放）与连接状态跟踪
  void _attachClient(RoomClient client) {
    client.attachGameHandler(_onClientGameMessage);
    client.addListener(_onClientChanged);
  }

  final RoomHost? _host;
  final RoomClient? _client;

  /// 棋盘路数（15/19，由房主建房时选定）
  final int boardSize;

  /// 我的座位号（1=房主执黑，2=客户端执白）
  final int mySeat;

  /// 已生效落子序列（索引奇偶决定黑白：偶=黑=座位1，奇=白=座位2）
  final List<(int, int)> moves = [];

  /// 胜方座位号；null 表示对局进行中
  int? winnerSeat;

  /// 胜负是否来自对方中途退出（而非五连）：终局弹窗文案据此区分
  bool wonByOpponentLeft = false;

  /// 校验拒绝等提示回调（页面接 SnackBar 展示；拒绝理由来自房主）
  void Function(String message)? onHint;

  /// 对局终止说明（对方离开/房主解散/连接断开）；
  /// 落子五连的胜负走 [winnerSeat]，不走此字段。
  /// 非 null 时页面弹窗告知并结束，之后不再恢复
  String? gameEndedText;

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
    if (_host != null) {
      _applyStone(col, row);
      return true;
    }
    _client?.send(
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

  /// 房主收客户端提交：校验轮次与落点，拒绝单独回执提交者，通过则广播生效
  /// （客户端不可信：本地拦截过的规则在房主侧全部重做）
  void _onHostGameMessage(int seat, NetMessage message) {
    if (message.type != NetMessageType.stoneSubmit) return;
    if (winnerSeat != null) return; // 对局已结束，忽略迟到的提交
    final col = message.payload['col'];
    final row = message.payload['row'];
    if (col is! int || row is! int) return;
    if (seat != currentSeat) {
      _host?.sendTo(seat, _resultMessage(false, 'notYourTurn'));
      return;
    }
    if (_occupied(col, row)) {
      _host?.sendTo(seat, _resultMessage(false, 'occupied'));
      return;
    }
    _host?.sendTo(seat, _resultMessage(true, null));
    _applyStone(col, row);
  }

  /// 落子生效：入列 + 五连判定；房主侧同步广播（五连时携带胜方座位）
  void _applyStone(int col, int row) {
    moves.add((col, row));
    if (_hasFiveInRow(col, row, moves.length.isOdd)) {
      // 刚落的子颜色 = 序列长度奇偶（1 手黑、2 手白……）
      winnerSeat = moves.length.isOdd ? 1 : 2;
    }
    notifyListeners();
    _host?.broadcast(
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

  /// 五连判定：以落子点为中心，沿四个方向数连续同色棋子
  /// 判定逻辑与本地对局页一致（规则同源，避免联机与本地行为不一致）
  bool _hasFiveInRow(int col, int row, bool black) {
    const dirs = [(1, 0), (0, 1), (1, 1), (1, -1)];
    for (final (dx, dy) in dirs) {
      var count = 1;
      for (final sign in [1, -1]) {
        var c = col + dx * sign;
        var r = row + dy * sign;
        while (_isSameStone(c, r, black)) {
          count++;
          c += dx * sign;
          r += dy * sign;
        }
      }
      if (count >= 5) return true;
    }
    return false;
  }

  /// 指定位置是否为指定颜色的已落棋子（越界视为无子）
  bool _isSameStone(int col, int row, bool black) {
    if (col < 0 || col >= boardSize || row < 0 || row >= boardSize) {
      return false;
    }
    for (var i = 0; i < moves.length; i++) {
      if (moves[i].$1 == col && moves[i].$2 == row) {
        return i.isEven == black;
      }
    }
    return false;
  }

  /// 房主侧：对方离开（掉线/主动退出）——2 人博弈无旁观者，直接判自己获胜
  void _onSeatLeft(int seat) {
    if (gameEndedText != null || winnerSeat != null) return;
    winnerSeat = mySeat;
    wonByOpponentLeft = true;
    notifyListeners();
    _host?.broadcast(
      NetMessage(
        type: NetMessageType.gameOver,
        payload: {'reason': 'opponentLeft', 'winner': mySeat},
      ),
    );
  }

  /// 客户端侧：处理房主对局消息，棋盘状态以广播为准
  void _onClientGameMessage(NetMessage message) {
    switch (message.type) {
      case NetMessageType.stoneApplied:
        final col = message.payload['col'];
        final row = message.payload['row'];
        if (col is! int || row is! int) return;
        moves.add((col, row));
        winnerSeat = message.payload['winner'] as int?;
        notifyListeners();
      case NetMessageType.stoneResult:
        // 拒绝才提示；通过无需处理（生效以 stoneApplied 广播为准）
        if (message.payload['ok'] != true) {
          onHint?.call(_reasonText(message.payload['reason']));
        }
      case NetMessageType.gameOver:
        winnerSeat = message.payload['winner'] as int?;
        wonByOpponentLeft = message.payload['reason'] == 'opponentLeft';
        notifyListeners();
      default:
        break;
    }
  }

  /// 客户端侧：连接状态变化（断线/房主解散 -> 对局终止）
  void _onClientChanged() {
    if (_client?.phase == RoomClientPhase.disconnected &&
        gameEndedText == null) {
      gameEndedText = _client!.disconnectText;
      notifyListeners();
    }
  }

  /// 房主拒绝原因 -> 用户可读文案
  String _reasonText(Object? reason) {
    switch (reason) {
      case 'notYourTurn':
        return '还没轮到你落子';
      case 'occupied':
        return '此处已有棋子';
      default:
        return '落子未被接受，请重试';
    }
  }

  /// 构造提交结果回执（仅发给提交者；拒绝时携带原因，null-aware 自动省略）
  NetMessage _resultMessage(bool ok, String? reason) => NetMessage(
        type: NetMessageType.stoneResult,
        payload: {'ok': ok, 'reason': ?reason},
      );

  @override
  void dispose() {
    // 页面销毁即退出对局：关闭底层房间连接
    // （房主解散会通知对方判胜，客户端退出会让房主判胜）
    _client?.removeListener(_onClientChanged);
    _host?.close();
    _client?.close();
    super.dispose();
  }
}
