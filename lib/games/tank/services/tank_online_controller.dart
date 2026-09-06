import 'dart:async';

import 'package:horyx/games/tank/game/bullet.dart';
import 'package:horyx/games/tank/game/tank.dart';
import 'package:horyx/games/tank/game/tank_maze_game.dart';
import 'package:horyx/games/tank/models/tank_player.dart';
import 'package:horyx/games/tank/services/tank_net_models.dart';
import 'package:horyx/shared/network/net_message.dart';
import 'package:horyx/shared/network/online_game_controller.dart';
import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/network/room_host.dart';

/// 坦克动荡联机对局控制器（房主权威 + 状态快照广播，见 tank_online_plan.md）
///
/// 与回合制联机（提交—校验—广播）不同，坦克是实时游戏：
/// - 房主端：本地跑完整模拟（[TankMazeGame] 本地模式，物理与回合
///   结算逻辑零改动），30Hz 广播战场状态快照；客户端的驾驶/开火
///   输入转发到本地战场执行；新局生成后广播迷宫种子（双端同种子
///   重建同一迷宫，不传输墙体数据）。
/// - 客户端：只上报输入（摇杆变化时发、开火即发），影子战场按收到的
///   快照驱动渲染，不做本地物理；开火音效由房主的即时事件驱动
///   （子弹本体仍由快照承载）。
///
/// 角色映射（与五子棋「创建者执黑」惯例一致）：
/// 房主（座位 1）= 红方，客户端（座位 2）= 绿方。
/// 比分/坦克/子弹的渲染在 [TankMazeGame] 内完成，本控制器只负责
/// 网络与游戏层之间的转接；比分变化通过 [notifyListeners] 通知页面。
class TankOnlineController extends OnlineGameControllerBase {
  /// 以房主身份接管房间（满员开局后由联机对局页调用）
  factory TankOnlineController.host(RoomHost host) {
    return TankOnlineController._(host: host, mySeat: 1)..initialize();
  }

  /// 以客户端身份接管房间（收到 gameStart 后由联机对局页调用）。
  /// gameStart 在挂接前可能已到达——对局消息由 RoomClient 暂存回放，
  /// 战场消息在战场挂接（[attachClientGame]）前再由本类二次暂存
  factory TankOnlineController.client(RoomClient client) {
    return TankOnlineController._(
      client: client,
      mySeat: client.mySeat ?? 2,
    )..initialize();
  }

  TankOnlineController._({super.host, super.client, required super.mySeat});

  /// 双人房间：对方固定为座位 2（绿方）；座位 1 为房主本机（红方）
  static const int _peerSeat = 2;

  /// 快照广播频率（30Hz）：局域网延迟下足够流畅，报文体积可控
  static const Duration _snapshotInterval = Duration(milliseconds: 33);

  /// 摇杆输入上报的变化阈值：角度/油门变化小于该值不重发
  /// （摇杆手抖产生的微幅抖动会刷爆报文；阈值小于操作可感知粒度。
  /// 取 0.03：上报粒度更细，房主端油门平滑的阶跃幅度更小、更流畅，
  /// tankDrive 单条约 70B，最坏 60 条/秒对局域网可忽略）
  static const double _driveEpsilon = 0.03;

  /// 已挂接的战场（房主=本地模拟；客户端=远程快照驱动）
  TankMazeGame? _game;

  // ---------- 房主端状态 ----------

  /// 20Hz 快照定时器（对局终止即取消）
  Timer? _snapshotTimer;

  /// 子弹身份映射（Bullet 未覆写 ==，按引用身份）：
  /// 快照里的子弹 id 需跨快照稳定，客户端据此匹配做平滑，
  /// 避免列表顺序变化导致渲染跳变
  final Map<Bullet, int> _bulletIds = {};
  int _nextBulletId = 1;

  // ---------- 客户端暂存（战场挂接前的消息，挂接时按序应用） ----------

  TankNetRoundStart? _pendingRoundStart;
  TankNetSnapshot? _pendingSnapshot;

  // ---------- 双端共用 ----------

  /// 上次通知页面的比分（变化才 notify，避免 20Hz 重建页面）
  int _lastRedScore = -1;
  int _lastGreenScore = -1;

  /// 客户端上次上报的摇杆输入（节流去重）
  TankDriveInput? _lastSentDrive;

  // ============ 战场挂接（联机对局页在 GameWidget 就绪后调用） ============

  /// 房主端：挂接本地模拟战场。
  /// 立即广播首局回合（首局迷宫在页面构造战场时已生成），
  /// 挂接新局回调（后续每局广播种子）并启动快照定时广播
  void attachHostGame(TankMazeGame game) {
    _game = game;
    game.onRoundStart = _broadcastCurrentRound;
    _broadcastCurrentRound();
    _snapshotTimer = Timer.periodic(_snapshotInterval, (_) => _broadcastSnapshot());
  }

  /// 客户端：挂接影子战场。挂接前收到的回合/快照消息按序应用：
  /// 先重建迷宫（种子），再应用最新快照（开局前双坦克位于出生点，
  /// 若快照还没到就先展示出生点）
  void attachClientGame(TankMazeGame game) {
    _game = game;
    final round = _pendingRoundStart;
    if (round != null) game.startRemoteRound(round);
    final snapshot = _pendingSnapshot;
    if (snapshot != null) game.applySnapshot(snapshot);
    _pendingRoundStart = null;
    _pendingSnapshot = null;
    _syncScores(snapshot);
  }

  // ============ 客户端输入上报（联机对局页摇杆/开火回调调用） ============

  /// 上报驾驶输入（null = 摇杆归位停车）；与上次差异小于阈值不重发
  void sendDrive(TankDriveInput? input) {
    if (client == null || gameEndedText != null) return;
    if (_sameInput(_lastSentDrive, input)) return;
    _lastSentDrive = input;
    client!.send(tankDriveMessage(input));
  }

  /// 上报开火请求（发射是否成功由房主裁决，客户端不预判）
  void sendFire() {
    if (client == null || gameEndedText != null) return;
    client!.send(tankFireMessage());
  }

  /// 房主开火：执行本地发射，成功即广播开火事件——客户端的发射音效
  /// 完全依赖该事件（房主自己开火也必须广播，否则客户端听不到）；
  /// 被同屏上限/结算期拒绝时不广播（客户端不多响一声）
  void hostFire() {
    if (gameEndedText != null) return;
    final game = _game;
    if (game == null) return;
    if (game.fire(TankPlayer.red)) {
      host?.broadcast(tankFireEventMessage(TankPlayer.red));
    }
  }

  /// 摇杆输入是否与上次等价（角度/油门均在阈值内视为未变化；
  /// 空与非空必然不等——停车与行驶是硬状态切换）
  static bool _sameInput(TankDriveInput? a, TankDriveInput? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return (a.targetAngle - b.targetAngle).abs() < _driveEpsilon &&
        (a.speedFactor - b.speedFactor).abs() < _driveEpsilon;
  }

  // ============ 房主端实现 ============

  /// 广播当前回合（首局与新局共用：从战场读迷宫规格/种子与比分）
  void _broadcastCurrentRound() {
    final game = _game;
    if (game == null || gameEndedText != null) return;
    final maze = game.maze;
    host?.broadcast(
      TankNetRoundStart(
        seed: maze.seed,
        cols: maze.cols,
        rows: maze.rows,
        redScore: game.redScore,
        greenScore: game.greenScore,
      ).toMessage(),
    );
  }

  /// 30Hz 快照广播；对局终止后自动停发
  void _broadcastSnapshot() {
    if (gameEndedText != null) {
      _snapshotTimer?.cancel();
      _snapshotTimer = null;
      return;
    }
    final game = _game;
    if (game == null) return;
    // 素材尚未加载完成（战场 onLoad 未跑完，坦克实体未创建）：
    // 快照缺坦克属于无效报文，跳过本次，待下个周期补发
    final red = game.tank(TankPlayer.red);
    final green = game.tank(TankPlayer.green);
    if (red == null || green == null) return;

    // 子弹 id 分配与身份清理：在场子弹先建映射，消失的（含到期/命中
    // 被移除的）清掉映射，长局不泄漏
    final bullets = <TankNetBulletState>[];
    final active = <Bullet>{};
    for (final entry in game.bulletsByPlayer.entries) {
      for (final bullet in entry.value) {
        active.add(bullet);
        var id = _bulletIds[bullet];
        if (id == null) {
          id = _nextBulletId++;
          _bulletIds[bullet] = id;
        }
        bullets.add(
          TankNetBulletState(
            id: id,
            owner: entry.key,
            x: bullet.logicalPos.x,
            y: bullet.logicalPos.y,
            angle: bullet.heading,
          ),
        );
      }
    }
    _bulletIds.removeWhere((bullet, _) => !active.contains(bullet));

    final snapshot = TankNetSnapshot(
      redScore: game.redScore,
      greenScore: game.greenScore,
      phase: game.phase,
      redTank: _tankState(red),
      greenTank: _tankState(green),
      bullets: bullets,
    );
    host?.broadcast(snapshot.toMessage());
    if (snapshot.redScore != _lastRedScore ||
        snapshot.greenScore != _lastGreenScore) {
      _syncScores(snapshot);
    }
  }

  /// 坦克快照条目组装
  TankNetTankState _tankState(Tank tank) => TankNetTankState(
        x: tank.logicalPos.x,
        y: tank.logicalPos.y,
        angle: tank.angle,
        destroyed: tank.destroyed,
      );

  /// 比分变化通知页面（比分条重建；坦克/子弹渲染不依赖页面重建）
  void _syncScores(TankNetSnapshot? snapshot) {
    final game = _game;
    final red = snapshot?.redScore ?? game?.redScore;
    final green = snapshot?.greenScore ?? game?.greenScore;
    if (red == null || green == null) return;
    if (red == _lastRedScore && green == _lastGreenScore) return;
    _lastRedScore = red;
    _lastGreenScore = green;
    notifyListeners();
  }

  /// 房主收客户端输入：驾驶转发到本地战场绿方，开火执行其本地开火逻辑
  /// （客户端不可信：载荷由解码函数校验，非法一律丢弃）
  @override
  void onHostGameMessage(int seat, NetMessage msg) {
    if (seat != _peerSeat) return;
    final game = _game;
    if (game == null || gameEndedText != null) return;
    switch (msg.type) {
      case NetMessageType.tankDrive:
        // 解码为 null 的两种情况（摇杆归位停车 / 非法载荷）统一按停车
        // 处理：置空输入，坦克停止旋转与推进。带角度的 speed 0 =
        // 圆钮在底座内的原地转向（只转不走，与本地双人语义一致）
        game.setNetworkDrive(TankPlayer.green, parseTankDrive(msg));
      case NetMessageType.tankFire:
        // 实际发射成功才广播事件：被上限/结算期拒绝时客户端不多响一声
        // （子弹本体由快照承载，事件只负责音效即时性）
        if (game.fire(TankPlayer.green)) {
          host?.broadcast(tankFireEventMessage(TankPlayer.green));
        }
      default:
        break;
    }
  }

  /// 房主侧：对方离开（掉线/主动退出）——对局直接结束，不判胜负
  /// （与五子棋/单词PK联机一致；停发快照，对方已收不到任何消息）
  @override
  void onSeatLeft(int seat) {
    if (gameEndedText != null) return;
    endGame(EndGameReason.peerLeft);
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    notifyListeners();
  }

  // ============ 客户端实现 ============

  /// 客户端收房主消息：回合开始重建迷宫、快照驱动影子战场、
  /// 开火事件播放音效。战场未挂接时回合/快照暂存（挂接时按序应用），
  /// 音效事件为过期即弃的即时信号，不暂存
  @override
  void onClientGameMessage(NetMessage msg) {
    switch (msg.type) {
      case NetMessageType.tankRoundStart:
        final round = TankNetRoundStart.fromMessage(msg);
        if (round == null) return;
        final game = _game;
        if (game == null) {
          _pendingRoundStart = round;
          _syncScoresFromRound(round);
          return;
        }
        game.startRemoteRound(round);
        _syncScoresFromRound(round);
      case NetMessageType.tankSnapshot:
        final snapshot = TankNetSnapshot.fromMessage(msg);
        if (snapshot == null) return;
        final game = _game;
        if (game == null) {
          _pendingSnapshot = snapshot; // 仅保留最新，旧快照无回放价值
          return;
        }
        game.applySnapshot(snapshot);
        _syncScores(snapshot);
      case NetMessageType.tankFireEvent:
        final owner = parseTankFireEvent(msg);
        if (owner == null) return;
        _game?.remoteFire(owner);
      default:
        break;
    }
  }

  /// 回合开始消息携带开新局时的比分：随迷宫重建同步给页面
  void _syncScoresFromRound(TankNetRoundStart round) {
    _syncScores(
      TankNetSnapshot(
        redScore: round.redScore,
        greenScore: round.greenScore,
        phase: TankBattlePhase.playing,
        redTank: _zeroTank,
        greenTank: _zeroTank,
        bullets: const [],
      ),
    );
  }

  @override
  void dispose() {
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    _game?.onRoundStart = null;
    _game = null;
    super.dispose();
  }
}

/// 全零坦克快照（回合开始比分同步的占位条目，位置由快照驱动无意义）
const _zeroTank = TankNetTankState(x: 0, y: 0, angle: 0, destroyed: false);
