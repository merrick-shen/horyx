import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:horyx/games/tank/game/bullet.dart';
import 'package:horyx/games/tank/game/effects/bullet_expire_effect.dart';
import 'package:horyx/games/tank/game/effects/tank_explosion_effect.dart';
import 'package:horyx/games/tank/game/tank.dart';
import 'package:horyx/games/tank/game/tank_audio.dart';
import 'package:horyx/games/tank/models/tank_maze.dart';
import 'package:horyx/games/tank/models/tank_player.dart';
import 'package:horyx/games/tank/services/tank_net_models.dart';

/// 坦克动荡战场游戏（Flame）：渲染每局随机生成的迷宫，并驱动坦克实体。
/// 迷宫按画布尺寸等比缩放并居中；墙体参数取自原版截图实测。
/// 坦克状态存于迷宫坐标系（与画布尺寸无关）：画布尺寸变化（进对局页的
/// 横屏旋转、前后台切换）只重建迷宫渲染并重新换算坦克渲染坐标，
/// 坦克位置与朝向不丢失；仅新生成迷宫（新对局）时回到出生点。
///
/// 两种运行模式（联机架构见 tank_online_plan.md）：
/// - 本地模拟（默认）：完整物理与回合结算，本地双人/房主端共用；
/// - 远程快照驱动（[remote]）：客户端影子战场，不做本地物理与结算，
///   状态全部由 [applySnapshot] 驱动，迷宫由 [startRemoteRound] 以
///   房主广播的种子重建，输入（setDrive/fire）被忽略并经控制器上报。
class TankMazeGame extends FlameGame {
  TankMazeGame({required this.maze, this.remote = false}) {
    _rebuildLogicalWalls();
  }

  /// 远程快照驱动模式：true 时禁用本地物理推进与命中结算
  final bool remote;

  /// 本局迷宫（每局开始时重新生成，见 [_startNewRound]）
  TankMaze maze;

  /// 重建墙体碰撞矩形（迷宫单位）。
  /// 墙段两端各延伸半个墙厚（0.05 格）覆盖转角接缝，与渲染一致。
  /// 原地清空重填：坦克持有同一列表引用，换迷宫后自动生效
  void _rebuildLogicalWalls() {
    _logicalWalls
      ..clear()
      ..addAll([
        for (final (x, y, vertical) in maze.walls)
          vertical
              ? Rect.fromLTWH(x - 0.05, y - 0.05, 0.10, 1.10)
              : Rect.fromLTWH(x - 0.05, y - 0.05, 1.10, 0.10),
      ]);
  }

  /// 双方坦克（按玩家索引，供摇杆输入下发）
  final Map<TankPlayer, Tank> _tanks = {};

  /// 双方在场子弹（按玩家分组，用于同屏上限计数）
  final Map<TankPlayer, List<Bullet>> _bulletsByPlayer = {};

  /// 每辆坦克同屏子弹上限：达上限后需等任一子弹消失才能继续发射
  static const int _maxBulletsPerTank = 5;

  // ============ 远程快照驱动模式（remote = true）专属状态 ============

  /// 坦克渲染平滑目标（迷宫坐标 + 朝向）：由最新快照写入，
  /// update 中指数平滑逼近。击毁的坦克不再平滑（隐身无意义）
  final Map<TankPlayer, (Vector2, double)> _tankTargets = {};

  /// 在场远程子弹（按房主分配的子弹 id 索引）：
  /// 快照按 id 匹配做平滑，避免列表顺序变化导致渲染跳变
  final Map<int, _RemoteBullet> _remoteBullets = {};

  /// 最新快照写入的战场阶段；只读暴露见 [phase]
  TankBattlePhase _phase = TankBattlePhase.playing;

  /// 最新快照的战场阶段（只读）：当前客户端无 UI 消费，
  /// 快照位置本身已表达定格/推进语义；预留供结算期 UI 与输入提示
  TankBattlePhase get phase => _phase;

  /// 坦克位置平滑系数（指数平滑速率，1/秒）：
  /// 20Hz 快照下滞后 ≈ 速度/系数（满速 2.6 格/秒约滞后 0.13 格，小于车宽）
  static const double _remoteSmoothK = 20.0;

  /// 已构建的迷宫组件（画布尺寸变化时先清空再重建）
  final List<Component> _mazeComponents = [];

  /// 墙体碰撞矩形（迷宫单位，原地重填以保持坦克持有的引用有效）
  final List<Rect> _logicalWalls = [];

  /// 画布几何：单元格边长（像素）与迷宫左上角偏移（渲染换算用）
  double _cell = 0;
  Vector2 _boardOffset = Vector2.zero();

  /// 坦克白模素材（onLoad 异步加载，加载完成前不出生坦克）
  Sprite? _bodySprite;
  Sprite? _cannonSprite;

  /// 子弹白模素材
  Sprite? _bulletSprite;

  /// 爆炸特效纹理（提取自坦克动荡 APK 的粒子纹理与图集）：
  /// 三角碎片白模、圆斑烟雾、爆闪软圆
  Sprite? _shardSprite;
  Sprite? _smokeSprite;
  Sprite? _flashSprite;

  /// 双方比分（对方坦克被击中即 +1，经 [onScored] 通知对局页）
  int redScore = 0;
  int greenScore = 0;

  /// 得分回调（对局页据此刷新比分 UI）
  void Function(TankPlayer player)? onScored;

  /// 一方被击毁后到开新一局的状态
  bool _roundOver = false;

  /// 结算倒计时（秒）：击毁后战场继续（残弹可命中），到点结算计分
  double _settleCountdown = 0;

  /// 战场冻结倒计时（秒）：计分完成后定格展示，到点开新一局
  double _freezeCountdown = 0;

  /// 本轮是否已计过分（双杀时本轮无人得分）
  bool _scored = false;

  /// 击毁后的结算等待（秒）：期间战场继续，残弹可继续反弹与命中（双杀可能发生）
  static const double _roundSettleDelay = 3.0;

  /// 计分完成后的战场冻结时长（秒）：定格展示后开新一局
  static const double _roundFreezeDelay = 1.0;

  /// 最近一次画布尺寸（开新一局重建迷宫用）
  Vector2? _lastCanvasSize;

  /// 画布透明：迷宫底板直接铺在对局页背景色上，
  /// 与原版一致（迷宫面板比页面底色略深一层）
  @override
  Color backgroundColor() => const Color(0x00000000);

  /// 对局页摇杆驾驶输入下发（player 对应的坦克执行转向/前进）。
  /// 已击毁的坦克忽略输入（战果展示期内存活坦克仍可正常驾驶）。
  /// 远程模式下输入不落地：本地不模拟对方坦克，由页面/控制器
  /// 改为上报网络（快照回来后驱动渲染），此处直接忽略
  void setDrive(TankPlayer player, TankDriveInput? input) {
    if (remote) return;
    _tanks[player]?.input = input;
  }

  /// 开火：从炮口沿车身朝向射出子弹。
  /// 每辆坦克同屏最多 5 发：达到上限后需等任一子弹消失才能继续发射。
  /// 已击毁的坦克不能再开火。
  /// 远程模式下开火同样不落地（子弹由房主快照同步），直接忽略
  void fire(TankPlayer player) {
    if (remote) return;
    // 计分定格期禁止开火：定格语义是全场静止，
    // 此时打出的子弹渲染一瞬即被新局清场，不该存在
    // （结算期允许开火是有意设计，残弹可命中制造双杀）
    if (_freezeCountdown > 0) return;
    final tank = _tanks[player];
    final sprite = _bulletSprite;
    if (tank == null || sprite == null || tank.destroyed) return;
    final bullets = _bulletsByPlayer.putIfAbsent(player, () => []);
    if (bullets.length >= _maxBulletsPerTank) return;

    final bullet = Bullet(
      walls: _logicalWalls,
      color: tank.color,
      sprite: sprite,
      logicalPos: tank.muzzleLogicalPos +
          Vector2(
            math.cos(tank.angle),
            math.sin(tank.angle),
          ) *
              Bullet.radius,
      angle: tank.angle,
    );
    bullets.add(bullet);
    add(bullet);
    TankAudio.shoot();
  }

  // onGameResize 在首次挂载与每次画布尺寸变化时都会调用。
  // 对局页强制横屏的旋转过程中画布尺寸会突变，布局必须按最新尺寸重建，
  // 否则迷宫停留在旧尺寸坐标系里（表现为过小且偏离中心）
  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (size.x <= 0 || size.y <= 0) return;
    _lastCanvasSize = size;
    _buildMaze(size);
    _ensureTanks();
    _syncTanks();
  }

  @override
  Future<void> onLoad() async {
    _bodySprite = Sprite(await _loadImage('assets/tank/tank_body.png'));
    _cannonSprite = Sprite(await _loadImage('assets/tank/tank_cannon.png'));
    _bulletSprite = Sprite(await _loadImage('assets/tank/bullet.png'));
    _shardSprite = Sprite(await _loadImage('assets/tank/tank_shard.png'));
    _smokeSprite = Sprite(await _loadImage('assets/tank/explosion_smoke.png'));
    _flashSprite = Sprite(await _loadImage('assets/tank/explosion_flash.png'));
    await TankAudio.preload();
    _ensureTanks();
    _syncTanks();
  }

  @override
  void update(double dt) {
    // 远程快照驱动模式：本地不做物理与回合结算——
    // 坦克由平滑目标驱动（super.update 对无 input 的坦克是空转），
    // 远程子弹在各自组件 update 中匀速推进朝快照位置，
    // 渲染同步照常执行；比分/阶段由快照直接写入
    if (remote) {
      super.update(dt);
      _smoothTanks(dt);
      _syncTanks();
      _syncBullets();
      return;
    }

    // 战场定格阶段：整体冻结（坦克/子弹都不推进，停在原地），
    // 倒计时到点开新一局；必须先于 super.update 判断，
    // 否则本帧子组件仍会被推进
    if (_freezeCountdown > 0) {
      _freezeCountdown -= dt;
      if (_freezeCountdown <= 0) _startNewRound();
      _syncTanks();
      _syncBullets();
      return;
    }

    // 先让坦克/子弹推进迷宫坐标系状态，再按最新状态同步渲染坐标
    super.update(dt);
    _pruneExpiredBullets();
    _checkBulletHits();

    if (_roundOver) {
      // 击毁战果展示期：残弹继续反弹与命中，倒计时结束结算计分
      _settleCountdown -= dt;
      if (_settleCountdown <= 0) {
        _settleScoring();
        _freezeCountdown = _roundFreezeDelay;
      }
    }

    _syncTanks();
    _syncBullets();
  }

  /// 命中判定：任一存活子弹命中任一存活坦克（含自己反弹的子弹）
  /// → 子弹消失、坦克击毁、对方得分，进入下一局倒计时。
  /// 先扫描收集命中、扫描结束后再统一结算：
  /// 结算会清空子弹分组列表，绝不能在遍历列表的过程中进行
  /// （清场与遍历同时发生会抛 concurrent modification 异常打断游戏循环）
  void _checkBulletHits() {
    TankPlayer? victim;
    for (final entry in _bulletsByPlayer.entries.toList()) {
      for (final bullet in entry.value.toList()) {
        for (final tankEntry in _tanks.entries) {
          final tank = tankEntry.value;
          if (tank.destroyed) continue;
          if (!tank.hitByCircle(bullet.logicalPos, Bullet.radius)) continue;
          victim = tankEntry.key;
          _spawnBulletExpire(bullet.position);
          bullet.removeFromParent();
          entry.value.remove(bullet);
          break;
        }
        if (victim != null) break;
      }
      if (victim != null) break;
    }
    if (victim != null) _onTankDestroyed(victim);
  }

  /// 坦克被击毁（此时命中子弹已移除）：受害者隐身并冻结其输入，
  /// 战场继续 3 秒（残弹可继续反弹与命中，双杀可能发生），
  /// 到点结算计分（存活方得分）→ 冻结 1 秒 → 开新一局
  void _onTankDestroyed(TankPlayer victim) {
    _tanks[victim]!
      ..destroyed = true
      ..input = null;
    _spawnExplosion(victim);
    _roundOver = true;
    _settleCountdown = _roundSettleDelay;
  }

  /// 击毁爆炸：音效 + 在爆点叠加爆炸特效（本地与远程快照驱动共用）。
  /// position 为上帧同步的屏幕坐标（击毁瞬间即最终位置）。
  /// 特效为纯渲染叠加组件，不参与碰撞，不影响子弹/坦克逻辑。
  /// 尺寸换算：素材坐标中坦克体长 48pt，本战场坦克缩放为 _cell 像素
  /// （scale=_cell），粒子参数（pt）乘 _cell/48 才能与坦克保持一致比例观感
  void _spawnExplosion(TankPlayer victim) {
    TankAudio.explosion();
    final shard = _shardSprite;
    final smoke = _smokeSprite;
    final flash = _flashSprite;
    if (shard != null && smoke != null && flash != null) {
      add(
        TankExplosionEffect(
          shardSprite: shard,
          smokeSprite: smoke,
          flashSprite: flash,
          position: _tanks[victim]!.position.clone(),
          color: _tanks[victim]!.color,
          sizeScale: _cell / 48,
          // 碎片撞墙查询：屏幕坐标 → 迷宫逻辑坐标，命中任一墙矩形即停
          hitTest: (p) {
            final lx = (p.x - _boardOffset.x) / _cell;
            final ly = (p.y - _boardOffset.y) / _cell;
            return _logicalWalls.any((w) => w.contains(Offset(lx, ly)));
          },
        ),
      );
    }
  }

  /// 结算计分：存活方得一分；双方都阵亡（展示期内残弹双杀）则本轮无人得分
  void _settleScoring() {
    if (_scored) return;
    final bothDead = _tanks.values.every((t) => t.destroyed);
    if (bothDead) return;

    final survivor = _tanks.entries.firstWhere((e) => !e.value.destroyed).key;
    if (survivor == TankPlayer.red) {
      redScore++;
    } else {
      greenScore++;
    }
    onScored?.call(survivor);
    _scored = true;
  }

  /// 开新一局：重新生成迷宫、坦克回出生点并复活、清空场上子弹（比分保留）
  void _startNewRound() {
    _applyNewMaze(TankMaze.generate());
  }

  /// 应用新迷宫并复位战场：本地新回合与远程回合开始（[startRemoteRound]）
  /// 共用的战场重建流程——换墙、重建渲染、坦克复位、清场
  void _applyNewMaze(TankMaze newMaze) {
    maze = newMaze;
    _rebuildLogicalWalls();
    if (_lastCanvasSize != null) _buildMaze(_lastCanvasSize!);
    _resetTanks();
    _clearBullets();
    _clearRemoteBullets();
    _clearEffects();
    _scored = false;
    _roundOver = false;
    _settleCountdown = 0;
    _freezeCountdown = 0;
  }

  /// 清除未消散完的特效（新一局开始时战场应干净）
  void _clearEffects() {
    removeWhere(
        (c) => c is TankExplosionEffect || c is BulletExpireEffect);
  }

  // ============ 远程快照驱动模式（remote = true）专属实现 ============

  /// 远程模式：回合开始（房主广播迷宫种子同步）。
  /// 以同种子重建同一迷宫并复位战场，比分取广播值；
  /// 坦克实际位置由随后的快照驱动
  void startRemoteRound(TankNetRoundStart round) {
    _applyNewMaze(
      TankMaze.generate(
        cols: round.cols,
        rows: round.rows,
        random: math.Random(round.seed),
      ),
    );
    redScore = round.redScore;
    greenScore = round.greenScore;
  }

  /// 远程模式：应用房主状态快照（比分/阶段/坦克/子弹）。
  /// 载荷已由控制器解码校验；坦克与子弹写入平滑目标，渲染逐帧逼近
  void applySnapshot(TankNetSnapshot snapshot) {
    redScore = snapshot.redScore;
    greenScore = snapshot.greenScore;
    _phase = snapshot.phase;

    _applyTankTarget(TankPlayer.red, snapshot.redTank);
    _applyTankTarget(TankPlayer.green, snapshot.greenTank);

    // 子弹按 id 增量同步：新 id 创建、已有 id 挪目标、
    // 消失的 id 移除并叠消散烟雾（与本地到期/命中的视觉一致）
    final seen = <int>{};
    final sprite = _bulletSprite;
    for (final state in snapshot.bullets) {
      seen.add(state.id);
      final existing = _remoteBullets[state.id];
      if (existing != null) {
        existing.retarget(state.x, state.y);
        continue;
      }
      // 素材未加载完成（onLoad 前）时暂不创建，待后续快照补齐
      if (sprite == null) continue;
      final bullet = _RemoteBullet(
        sprite: sprite,
        color: state.owner.color,
        logicalPos: Vector2(state.x, state.y),
      );
      _remoteBullets[state.id] = bullet;
      add(bullet);
    }
    _remoteBullets.removeWhere((id, bullet) {
      if (seen.contains(id)) return false;
      // 消失位置按逻辑坐标换算：新子弹可能在首次渲染同步前就被移除
      _spawnBulletExpire(_boardOffset + bullet.logicalPos * _cell);
      bullet.removeFromParent();
      return true;
    });
  }

  /// 远程模式：开火音效事件（房主即时广播）。
  /// 子弹本体的出现由快照承载，这里只负责声音的即时性；
  /// player 为开火方（保留语义，当前双端音效一致）
  void remoteFire(TankPlayer player) {
    TankAudio.shoot();
  }

  /// 写入单辆坦克的快照平滑目标；
  /// destroyed 由存活变为击毁时触发爆炸特效（远程端唯一的爆炸触发点）
  void _applyTankTarget(TankPlayer player, TankNetTankState state) {
    final tank = _tanks[player];
    if (tank == null) return; // 素材未加载完成（onLoad 前），跳过待下帧
    if (state.destroyed && !tank.destroyed) {
      tank.destroyed = true;
      _spawnExplosion(player);
    } else if (!state.destroyed && tank.destroyed) {
      // 击毁→复活仅出现在新回合（TCP 按序下先收 roundStart 复位，
      // 此处为快照先于回合消息的时序兜底）
      tank.destroyed = false;
    }
    _tankTargets[player] = (Vector2(state.x, state.y), state.angle);
  }

  /// 坦克渲染平滑：朝最新快照目标指数逼近（位置 + 最短弧朝向）。
  /// 击毁的坦克跳过（隐身由渲染同步缩放归零处理）
  void _smoothTanks(double dt) {
    final t = 1 - math.exp(-_remoteSmoothK * dt);
    for (final entry in _tankTargets.entries) {
      final tank = _tanks[entry.key];
      if (tank == null || tank.destroyed) continue;
      final (target, targetAngle) = entry.value;
      tank.logicalPos += (target - tank.logicalPos) * t;
      tank.angle += Tank.angleDelta(tank.angle, targetAngle) * t;
    }
  }

  /// 清空全部远程子弹（新回合清场用；本地模式恒为空集）
  void _clearRemoteBullets() {
    for (final bullet in _remoteBullets.values) {
      bullet.removeFromParent();
    }
    _remoteBullets.clear();
  }

  /// 坦克复位：回出生点、朝向复位、复活并清空输入
  void _resetTanks() {
    _tanks[TankPlayer.red]
      ?..logicalPos = Vector2(0.5, maze.rows - 0.5)
      ..angle = 0
      ..input = null
      ..destroyed = false;
    _tanks[TankPlayer.green]
      ?..logicalPos = Vector2(maze.cols - 0.5, 0.5)
      ..angle = math.pi
      ..input = null
      ..destroyed = false;
    _syncTanks();
  }

  /// 清空场上全部子弹（新一局开始/击毁结算）。
  /// 只清各分组列表、保留 map 结构：命中判定正遍历该 map，
  /// 在遍历中 clear map 会抛 concurrent modification 异常
  void _clearBullets() {
    for (final bullets in _bulletsByPlayer.values) {
      for (final bullet in bullets) {
        bullet.removeFromParent();
      }
      bullets.clear();
    }
  }

  /// 移除到寿命的子弹（组件与同屏计数同步清理）。
  /// 射程极限消失时叠加消散特效
  void _pruneExpiredBullets() {
    for (final entry in _bulletsByPlayer.entries) {
      for (final bullet in entry.value.where((b) => b.expired)) {
        _spawnBulletExpire(bullet.position);
        bullet.removeFromParent();
      }
      entry.value.removeWhere((b) => b.expired);
    }
  }

  /// 子弹消失消散特效：position 为上帧同步的屏幕坐标。
  /// 纯渲染叠加组件，不参与碰撞，不影响子弹/坦克逻辑
  void _spawnBulletExpire(Vector2 screenPos) {
    final smoke = _smokeSprite;
    if (smoke == null) return;
    add(
      BulletExpireEffect(
        smokeSprite: smoke,
        position: screenPos.clone(),
        sizeScale: _cell / 48,
      ),
    );
  }

  /// 把子弹逻辑状态换算为渲染坐标（中心像素位置 + 单元格缩放）
  void _syncBullets() {
    if (_cell == 0) return;
    for (final bullets in _bulletsByPlayer.values) {
      for (final bullet in bullets) {
        bullet
          ..position = _boardOffset + bullet.logicalPos * _cell
          ..scale = Vector2.all(_cell);
      }
    }
  }

  /// 读取打包素材为 Flame 图片（资产在 assets/tank/，不经 Flame 默认的
  /// assets/images/ 前缀，直接走 rootBundle 加载）
  Future<ui.Image> _loadImage(String asset) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// 出生双方坦克（仅首次）：红方左下角朝右、绿方右上角朝左（点对称）。
  /// 画布尺寸变化不重建坦克——位置/朝向存于迷宫坐标系，换算后原样保留
  void _ensureTanks() {
    if (_tanks.isNotEmpty || _bodySprite == null || _cell == 0) return;
    final body = _bodySprite!;
    final cannon = _cannonSprite!;

    final red = Tank(
      walls: _logicalWalls,
      color: TankPlayer.red.color,
      bodySprite: body,
      cannonSprite: cannon,
      logicalPos: Vector2(0.5, maze.rows - 0.5),
      angle: 0,
    );
    final green = Tank(
      walls: _logicalWalls,
      color: TankPlayer.green.color,
      bodySprite: body,
      cannonSprite: cannon,
      logicalPos: Vector2(maze.cols - 0.5, 0.5),
      angle: math.pi,
    );
    red.opponent = green;
    green.opponent = red;

    _tanks[TankPlayer.red] = red;
    _tanks[TankPlayer.green] = green;
    add(red);
    add(green);
  }

  /// 把坦克逻辑状态换算为渲染坐标（中心像素位置 + 单元格缩放）。
  /// 被击毁的坦克缩放归零隐身
  void _syncTanks() {
    if (_cell == 0) return;
    for (final entry in _tanks.entries) {
      final tank = entry.value;
      tank
        ..position = _boardOffset + tank.logicalPos * _cell
        ..scale = Vector2.all(tank.destroyed ? 0.0 : _cell);
    }
  }

  /// 按画布尺寸重建迷宫组件
  void _buildMaze(Vector2 canvasSize) {
    removeAll(_mazeComponents);
    _mazeComponents.clear();

    // 单元格边长取画布宽高能容纳的较小值，迷宫整体居中
    final cell = math.min(canvasSize.x / maze.cols, canvasSize.y / maze.rows);
    final thickness = cell * _wallThicknessRatio;
    final offsetX = (canvasSize.x - cell * maze.cols) / 2;
    final offsetY = (canvasSize.y - cell * maze.rows) / 2;
    _cell = cell;
    _boardOffset = Vector2(offsetX, offsetY);

    // 迷宫底板
    _add(
      RectangleComponent(
        position: Vector2(offsetX, offsetY),
        size: Vector2(cell * maze.cols, cell * maze.rows),
        paint: Paint()..color = _floorColor,
      ),
    );

    final wallPaint = Paint()..color = _wallColor;
    for (final (x, y, vertical) in maze.walls) {
      // 墙段两端各延伸半个墙厚，填补十字/转角处的接缝
      final rect = vertical
          ? Rect.fromLTWH(
              offsetX + x * cell - thickness / 2,
              offsetY + y * cell - thickness / 2,
              thickness,
              cell + thickness,
            )
          : Rect.fromLTWH(
              offsetX + x * cell - thickness / 2,
              offsetY + y * cell - thickness / 2,
              cell + thickness,
              thickness,
            );
      _add(
        RectangleComponent(
          position: Vector2(rect.left, rect.top),
          size: Vector2(rect.width, rect.height),
          paint: wallPaint,
        ),
      );
    }
  }

  /// 添加组件并记录，供画布尺寸变化时清除重建
  void _add(Component component) {
    add(component);
    _mazeComponents.add(component);
  }

  /// 墙体颜色（原版取色）
  static const Color _wallColor = Color(0xFF4C4C4C);

  /// 迷宫底板颜色（原版为比页面白底略深的浅灰面板）
  static const Color _floorColor = Color(0xFFE6E6E6);

  /// 墙厚约占单元格边长的比例（原版实测约 10%）
  static const double _wallThicknessRatio = 0.10;
}

/// 远程子弹：纯渲染组件（不参与本地物理与碰撞），位置由状态快照驱动。
/// 渲染平滑：每帧以真实飞行速度（[Bullet.speed]）朝最新快照位置
/// 匀速推进——直线段无滞后地衔接下帧快照，反弹折点呈短弧过渡，
/// 比阶梯跳动顺滑；快照间隔短时两者几乎重合
class _RemoteBullet extends PositionComponent {
  _RemoteBullet({
    required Sprite sprite,
    required Color color,
    required Vector2 logicalPos,
  })  : logicalPos = logicalPos.clone(),
        _target = logicalPos.clone() {
    anchor = Anchor.center;
    priority = 1;
    size = Vector2.all(Bullet.radius * 2);
    add(
      SpriteComponent(
        sprite: sprite,
        size: Vector2.all(Bullet.radius * 2),
        paint: Paint()..colorFilter = tintFilter(color),
      ),
    );
  }

  /// 子弹中心在迷宫坐标系下的位置（单位=格，与本地子弹同名同语义，
  /// 供战场渲染同步与消失特效换算共用）
  Vector2 logicalPos;

  /// 最新快照位置（平滑目标）
  Vector2 _target;

  /// 快照更新平滑目标
  void retarget(double x, double y) {
    _target = Vector2(x, y);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final delta = _target - logicalPos;
    final dist = delta.length;
    if (dist <= 1e-6) return;
    final step = math.min(Bullet.speed * dt, dist);
    logicalPos += delta * (step / dist);
  }
}
