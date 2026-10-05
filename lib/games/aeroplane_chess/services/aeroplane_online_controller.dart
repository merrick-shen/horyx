import 'dart:math';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';
import 'package:horyx/games/aeroplane_chess/services/aeroplane_engine.dart';
import 'package:horyx/games/aeroplane_chess/services/aeroplane_net_models.dart';
import 'package:horyx/shared/network/net_message.dart';
import 'package:horyx/shared/network/online_game_controller.dart';
import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/network/room_host.dart';

/// 飞行棋联机对局控制器（房主权威 + 全量快照重同步）
/// 公共骨架（连接持有/挂接/断线终局/生命周期）见基类
/// [OnlineGameControllerBase]，走子拒绝回执能力来自混入
/// [SubmissionReceiptMixin]。与「提交—校验—增量广播」的棋类不同，
/// 飞行棋回合内含掷骰随机与连锁迁移，采用快照协议：
/// - 客户端发掷骰请求，房主生成骰点并广播掷骰结果（骰子只在房主侧）；
/// - 掷出三 6 惩罚或无可动棋子时房主立即迁移并广播状态，无需走子提交；
/// - 客户端发走子提交（棋子编号 + 是否飞越），房主用与本地同源的
///   [AeroplaneEngine] 判定迁移后广播全量状态快照重同步；
/// - 掷骰结果与状态快照共用房主侧递增序号，客户端按序幂等应用，
///   防御消息重复与乱序；
/// - 任一玩家中途离开（掉线/主动退出）对局立即结束并广播终局
///   （断线即终局退出，无对局重连；缺席方的棋子无人操作，对局无法继续）。
/// 座位与颜色：座位顺序即玩家列表顺序（房主 1 号位），颜色分配与本地
/// 对局同源（[AeroplaneGameState.defaultColors]），行动顺序由引擎状态承载。
class AeroplaneOnlineController extends OnlineGameControllerBase
    with SubmissionReceiptMixin {
  /// 以房主身份接管房间（满员开局后由等待页调用）：
  /// 构建初始对局状态（座位顺序 = 玩家顺序）并立即广播首个快照——
  /// 客户端控制器挂接前的消息由 RoomClient 暂存回放，不会丢失。
  /// [random] 仅测试注入固定骰点序列用，默认 [Random]
  factory AeroplaneOnlineController.host(RoomHost host, {Random? random}) {
    final controller = AeroplaneOnlineController._(
      host: host,
      mySeat: 1,
      playerCount: host.capacity,
      seatNames: {for (final seat in host.seats) seat: host.nameOf(seat)},
    );
    if (random != null) controller._random = random;
    final players = [
      for (var i = 0; i < host.capacity; i++)
        AeroplanePlayer(
          color: AeroplaneGameState.defaultColors[host.capacity]![i],
          name: host.nameOf(i + 1),
        ),
    ];
    controller.state = AeroplaneGameState.initial(players);
    controller.initialize();
    controller.host?.broadcast(
      aeroplaneStateMessage(
        seq: controller._nextSeq(),
        state: controller.state!,
      ),
    );
    return controller;
  }

  /// 以客户端身份接管房间（收到 gameStart 后由等待页调用）。
  /// 首个状态快照在挂接前可能已到达——由 RoomClient 暂存，
  /// [initialize] 挂接时按序回放，构造完成后 [state] 即已同步
  factory AeroplaneOnlineController.client(RoomClient client) {
    return AeroplaneOnlineController._(
      client: client,
      mySeat: client.mySeat ?? 2,
      playerCount: client.capacity,
      seatNames: Map<int, String>.of(client.seatNames),
    )..initialize();
  }

  AeroplaneOnlineController._({
    super.host,
    super.client,
    required super.mySeat,
    required this.playerCount,
    required this.seatNames,
  });

  /// 本局总人数（构造参数注入：与挂接时机解耦，无 late 初始化时序约束）
  final int playerCount;

  /// 座位 -> 名字快照（构造注入的不可变映射，开局时定格，对局中改名不影响）
  final Map<int, String> seatNames;

  /// 当前对局状态（房主开局即构建；客户端等待首个快照同步，
  /// 之后随房主广播全量替换）
  AeroplaneGameState? state;

  /// 当前回合未消费的骰点：房主掷骰后置位、迁移广播后清空；
  /// 客户端随掷骰结果广播置位、随快照应用清空。null = 等待掷骰
  int? pendingDice;

  /// 房主侧骰子随机源（骰子只在房主侧生成，客户端不自行产生点数）
  Random _random = Random();

  /// 房主侧权威广播递增序号（掷骰结果与状态快照共用，每次广播自增）
  int _seq = 0;

  /// 客户端侧已应用的最新序号：小于等于它的广播幂等丢弃（防重复与乱序）
  int _lastSeq = 0;

  // ---- 座位 / 颜色 / 回合推导 ----

  /// 我的颜色（座位顺序即玩家列表顺序）；状态未同步或座位越界返回 null
  AeroplaneColor? get myColor {
    final s = state;
    if (s == null || mySeat < 1 || mySeat > s.players.length) return null;
    return s.players[mySeat - 1].color;
  }

  /// 颜色 → 座位号（玩家列表顺序即座位顺序）；状态未同步或不存在返回 0
  int seatOfColor(AeroplaneColor color) {
    final s = state;
    if (s == null) return 0;
    return s.players.indexWhere((p) => p.color == color) + 1;
  }

  /// 当前行动方座位号（状态未同步返回 0）
  int get currentSeat {
    final s = state;
    return s == null ? 0 : seatOfColor(s.currentPlayer);
  }

  /// 是否轮到自己行动（掷骰/走子共用；终局后禁止继续）
  bool get isMyTurn {
    final s = state;
    if (s == null || s.gameOver || gameEndedText != null) return false;
    return currentSeat == mySeat;
  }

  /// 胜方座位号；对局进行中或无胜负终局返回 null
  int? get winnerSeat {
    final winner = state?.winner;
    return winner == null ? null : seatOfColor(winner);
  }

  // ---- 玩家入口（页面调用） ----

  /// 掷骰：房主本地生成骰点并广播；客户端发请求交房主生成。
  /// 非本人回合提示拒绝；本回合已掷骰（等待走子）时静默不受理
  bool rollDice() {
    final s = state;
    if (s == null || s.gameOver || gameEndedText != null) return false;
    if (!isMyTurn) {
      onHint?.call('还没轮到你掷骰');
      return false;
    }
    if (pendingDice != null) return false;
    if (host != null) {
      _applyRoll(_random.nextInt(6) + 1);
      return true;
    }
    client?.send(aeroplaneRollRequestMessage());
    return true;
  }

  /// 提交走子（页面选中棋子确认后调用；[fly] 为是否沿加油站航线飞越）。
  /// 本地先按与房主同源的引擎预检（省一次往返），真实性仍由房主裁决；
  /// 返回 true 表示已受理（房主模式即生效）
  bool submitMove(int planeId, {bool fly = false}) {
    final s = state;
    if (s == null || s.gameOver || gameEndedText != null) return false;
    if (!isMyTurn) {
      onHint?.call('还没轮到你走子');
      return false;
    }
    final dice = pendingDice;
    if (dice == null) {
      onHint?.call('请先掷骰子再走子');
      return false;
    }
    final color = myColor;
    if (color == null) return false;
    final move = AeroplaneMove(color: color, planeId: planeId, fly: fly);
    if (!AeroplaneEngine.legalMoves(s, dice).contains(move)) {
      onHint?.call('这不是合法走法');
      return false;
    }
    if (host != null) {
      _applyAndBroadcast(AeroplaneEngine.applyMove(s, move, dice));
      return true;
    }
    client?.send(aeroplaneMoveSubmitMessage(planeId: planeId, fly: fly));
    return true;
  }

  // ---- 房主侧实现 ----

  /// 房主收客户端消息：掷骰请求与走子提交（终局后一律忽略）
  @override
  void onHostGameMessage(int seat, NetMessage message) {
    if (gameEndedText != null) return;
    switch (message.type) {
      case NetMessageType.aeroplaneRollRequest:
        _onHostRollRequest(seat);
      case NetMessageType.aeroplaneMoveSubmit:
        _onHostMoveSubmit(seat, message);
      default:
        break;
    }
  }

  /// 房主收掷骰请求：仅受理当前行动方且未掷骰的请求，
  /// 其余（非本人回合/重复请求/终局）静默忽略，不回执
  void _onHostRollRequest(int seat) {
    final s = state;
    if (s == null || s.gameOver) return;
    if (seat != currentSeat || pendingDice != null) return;
    _applyRoll(_random.nextInt(6) + 1);
  }

  /// 掷骰结算（房主侧唯一入口）：广播骰点，随后分支——
  /// 三 6 惩罚 / 无可动棋子跳过（均立即迁移并广播状态）/ 等待走子提交
  void _applyRoll(int dice) {
    final s = state;
    if (s == null || s.gameOver) return;
    pendingDice = dice;
    notifyListeners();
    host?.broadcast(AeroplaneNetRoll(value: dice, seq: _nextSeq()).toMessage());
    if (AeroplaneEngine.isThirdSixPenalty(s, dice)) {
      _applyAndBroadcast(AeroplaneEngine.applyThirdSixPenalty(s));
      return;
    }
    if (AeroplaneEngine.legalMoves(s, dice).isEmpty) {
      _applyAndBroadcast(AeroplaneEngine.skipTurn(s));
    }
  }

  /// 房主收走子提交：轮次 -> 骰点 -> 合法性逐层校验（客户端不可信：
  /// 本地预检过的规则在房主侧用同一引擎全部重做），拒绝回执提交者，
  /// 通过则迁移并广播全量快照
  void _onHostMoveSubmit(int seat, NetMessage message) {
    final s = state;
    if (s == null || s.gameOver) return;
    final submit = parseAeroplaneMoveSubmit(message);
    if (submit == null) return; // 字段缺失/编号越界，静默丢弃
    if (seat != currentSeat) {
      host?.sendTo(seat, resultMessage(false, 'notYourTurn'));
      return;
    }
    final dice = pendingDice;
    if (dice == null) {
      host?.sendTo(seat, resultMessage(false, 'noDice'));
      return;
    }
    final move = AeroplaneMove(
      color: s.currentPlayer,
      planeId: submit.planeId,
      fly: submit.fly,
    );
    if (!AeroplaneEngine.legalMoves(s, dice).contains(move)) {
      host?.sendTo(seat, resultMessage(false, 'invalidMove'));
      return;
    }
    host?.sendTo(seat, resultMessage(true, null));
    _applyAndBroadcast(AeroplaneEngine.applyMove(s, move, dice));
  }

  /// 迁移生效：更新本地状态并广播全量快照（骰点随之消费清空）
  void _applyAndBroadcast(AeroplaneGameState next) {
    state = next;
    pendingDice = null;
    notifyListeners();
    host?.broadcast(aeroplaneStateMessage(seq: _nextSeq(), state: next));
  }

  /// 房主侧权威广播序号自增（掷骰结果与状态快照共用同一序号空间）
  int _nextSeq() => ++_seq;

  /// 房主侧：任一玩家离开（掉线/主动退出）对局立即结束，不判胜负，
  /// 并广播终局给其余在线玩家（2 人局无人可收，广播无副作用）
  @override
  void onSeatLeft(int seat) {
    if (gameEndedText != null) return;
    endGame(EndGameReason.peerLeft);
    host?.broadcast(
      const NetMessage(
        type: NetMessageType.gameOver,
        payload: {'reason': 'peerLeft'},
      ),
    );
    notifyListeners();
  }

  // ---- 客户端侧实现 ----

  /// 客户端收房主消息：状态以广播为准，按序号幂等应用（终局后忽略）
  @override
  void onClientGameMessage(NetMessage message) {
    if (gameEndedText != null) return;
    switch (message.type) {
      case NetMessageType.aeroplaneRollResult:
        final roll = AeroplaneNetRoll.fromMessage(message);
        if (roll == null || roll.seq <= _lastSeq) return;
        _lastSeq = roll.seq;
        pendingDice = roll.value;
        notifyListeners();
      case NetMessageType.aeroplaneState:
        final snapshot = parseAeroplaneState(message);
        if (snapshot == null || snapshot.seq <= _lastSeq) return;
        _lastSeq = snapshot.seq;
        _applyClientState(snapshot.state);
      case NetMessageType.aeroplaneMoveResult:
        // 拒绝才提示；通过无需处理（生效以状态快照广播为准）
        if (message.payload['ok'] != true) {
          onHint?.call(reasonText(message.payload['reason']));
        }
      case NetMessageType.gameOver:
        // 其他玩家离开：房主广播的无胜负终局
        endGame(EndGameReason.peerLeft);
        notifyListeners();
      default:
        break;
    }
  }

  /// 应用房主全量快照：校验自己的座位在玩家之列后整体替换本地状态
  /// （矛盾快照说明状态不可信且无重同步手段，走 dataError 终局，
  /// 与五子棋开局载荷校验同一防御等级）
  void _applyClientState(AeroplaneGameState next) {
    if (mySeat < 1 || mySeat > next.players.length) {
      endGame(EndGameReason.dataError);
      notifyListeners();
      return;
    }
    state = next;
    pendingDice = null;
    notifyListeners();
  }

  // ---- 回执混入实现 ----

  /// 房主拒绝原因 -> 用户可读文案
  @override
  String reasonText(Object? reason) {
    switch (reason) {
      case 'notYourTurn':
        return '还没轮到你走子';
      case 'noDice':
        return '请先掷骰子再走子';
      case 'invalidMove':
        return '这不是合法走法';
      default:
        return '走子未被接受，请重试';
    }
  }

  /// 提交回执的消息类型（飞行棋为 aeroplaneMoveResult）
  @override
  NetMessageType get resultMessageType => NetMessageType.aeroplaneMoveResult;
}
