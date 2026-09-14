import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'package:horyx/games/tank/engine/bullet.dart';
import 'package:horyx/games/tank/engine/tank.dart';
import 'package:horyx/games/tank/engine/tank_audio.dart';
import 'package:horyx/games/tank/models/tank_battle_phase.dart';
import 'package:horyx/games/tank/models/tank_maze.dart';
import 'package:horyx/games/tank/models/tank_player.dart';
import 'package:horyx/games/tank/services/tank_net_models.dart';
import 'package:horyx/games/tank/tint_filter.dart';

/// 远程影子战场驱动器对宿主战场的依赖契约（[TankMazeGame] 实现）。
/// 驱动器只经由该契约操作战场，不感知本地物理与回合结算；
/// 契约成员均为战场既有能力的最小暴露
abstract interface class RemoteBattleHost {
  /// 按玩家取坦克（素材加载完成前为 null）
  Tank? tank(TankPlayer player);

  /// 双方比分（远程快照值直接写入）
  abstract int redScore;
  abstract int greenScore;

  /// 子弹白模素材（onLoad 完成前为 null，此时暂缓创建远程子弹）
  Sprite? get bulletSprite;

  /// 画布几何：单元格边长（像素）
  double get cell;

  /// 迷宫逻辑坐标 → 屏幕坐标（特效定位用）
  Vector2 logicalToScreen(Vector2 logicalPos);

  /// 挂载组件到战场组件树
  void addComponent(Component component);

  /// 击毁爆炸（音效 + 特效），本地与远程共用
  void spawnExplosion(TankPlayer victim);

  /// 子弹消散特效（position 为屏幕坐标）
  void spawnBulletExpire(Vector2 screenPos);

  /// 以指定迷宫重建战场：换墙、重建渲染、坦克复位、清场、远程状态复位
  void resetBattlefield(TankMaze maze);
}

/// 远程影子战场驱动器（客户端模式专属协作类）：
/// 不做本地物理与回合结算，战场渲染全部由房主快照驱动——
/// 坦克朝按快照年龄外推的移动目标指数平滑逼近；远程子弹按快照 id
/// 增量同步并沿飞行方向外推；比分/阶段由快照直接写入。
/// 击毁/反弹等事件的音效特效按快照语义推断补播
/// （联机架构见 tank_online_plan.md）
class RemoteBattleDriver {
  RemoteBattleDriver(this._host);

  final RemoteBattleHost _host;

  /// 坦克位置平滑目标（迷宫坐标 + 朝向）：由最新快照写入，
  /// update 中指数平滑逼近。击毁的坦克不再平滑（隐身无意义）
  final Map<TankPlayer, (Vector2, double)> _tankTargets = {};

  /// 坦克平滑估计速度（迷宫格/秒）：由相邻快照差分估计（限幅坦克极速），
  /// 快照间匀速外推——指数逼近固定目标会让坦克每个快照周期"追上后减速
  final Map<TankPlayer, Vector2> _tankVelocities = {};

  /// 上次快照到达时刻（秒，墙钟）：差分速度估计用
  final Map<TankPlayer, double> _lastTargetTime = {};

  /// 在场远程子弹（按房主分配的子弹 id 索引）：
  /// 快照按 id 匹配做平滑，避免列表顺序变化导致渲染跳变
  final Map<int, _RemoteBullet> _remoteBullets = {};

  /// 最新快照写入的战场阶段；只读暴露见 [phase]
  TankBattlePhase _phase = TankBattlePhase.playing;

  /// 当前战场阶段（只读）：取最新快照写入值
  TankBattlePhase get phase => _phase;

  /// 坦克位置平滑系数（指数平滑速率，1/秒）：
  /// 30Hz 快照下滞后 ≈ 速度/系数（满速 2.6 格/秒约滞后 0.13 格，小于车宽）
  static const double _remoteSmoothK = 20.0;

  /// 快照年龄外推上限（秒，约 3 个快照周期）：渲染目标 = 快照位置 +
  /// 估计速度 × 快照年龄，快照晚到时目标持续前进消除停顿；超过上限
  /// （断流）后目标冻结在延伸位置，避免按旧速度无限外推冲出战场。
  /// 上限放宽到 0.1s 容忍偶发到达抖动（满速外推 0.1s 偏差约 0.26 格，
  /// 下条快照即校正）
  static const double _maxExtrapolateAge = 0.1;

  /// 最新快照到达时刻（秒，墙钟）：外推年龄基准
  double _lastSnapshotAt = 0;

  /// 本帧快照年龄（[beginFrame] 计算写入，[smoothTanks] 复用）
  double _frameAge = 0;

  /// 回合开始（房主广播迷宫种子同步）：以同种子重建同一迷宫并复位战场
  /// （经宿主 [RemoteBattleHost.resetBattlefield] 联动复位驱动器状态），
  /// 比分取广播值；坦克实际位置由随后的快照驱动
  void startRemoteRound(TankNetRoundStart round) {
    _host.resetBattlefield(
      TankMaze.generate(
        cols: round.cols,
        rows: round.rows,
        seed: round.seed,
      ),
    );
    _host.redScore = round.redScore;
    _host.greenScore = round.greenScore;
  }

  /// 应用房主状态快照（比分/阶段/坦克/子弹）。
  /// 载荷已由控制器解码校验；坦克与子弹写入平滑目标，渲染逐帧逼近
  void applySnapshot(TankNetSnapshot snapshot) {
    _lastSnapshotAt = _nowSec();
    _host.redScore = snapshot.redScore;
    _host.greenScore = snapshot.greenScore;
    _phase = snapshot.phase;

    // 先处理坦克：记录本快照是否有坦克刚被击毁——命中场景子弹同时消失，
    // 爆炸声已表达战果，子弹消失不再叠播消散音效
    final justDestroyed = _applyTankTarget(TankPlayer.red, snapshot.redTank) |
        _applyTankTarget(TankPlayer.green, snapshot.greenTank);

    // 子弹按 id 增量同步：新 id 创建、已有 id 挪目标、
    // 消失的 id 移除并叠消散烟雾（与本地到期/命中的视觉一致）
    final seen = <int>{};
    final sprite = _host.bulletSprite;
    for (final state in snapshot.bullets) {
      seen.add(state.id);
      final existing = _remoteBullets[state.id];
      if (existing != null) {
        existing.retarget(state.x, state.y, state.angle);
        continue;
      }
      // 素材未加载完成（onLoad 前）时暂不创建，待后续快照补齐
      if (sprite == null) continue;
      final bullet = _RemoteBullet(
        sprite: sprite,
        color: state.owner.color,
        logicalPos: Vector2(state.x, state.y),
        heading: state.angle,
      );
      _remoteBullets[state.id] = bullet;
      _host.addComponent(bullet);
    }
    _remoteBullets.removeWhere((id, bullet) {
      if (seen.contains(id)) return false;
      // 消失位置按逻辑坐标换算：新子弹可能在首次渲染同步前就被移除
      _host.spawnBulletExpire(_host.logicalToScreen(bullet.logicalPos));
      // 消失音效同本地到期语义；命中场景（同快照有坦克刚击毁）由爆炸声表达
      if (!justDestroyed) TankAudio.bulletExpire();
      bullet.removeFromParent();
      return true;
    });
  }

  /// 写入单辆坦克的快照平滑目标，并差分估计其速度（供快照间匀速外推）；
  /// destroyed 由存活变为击毁时触发爆炸特效（远程端唯一的爆炸触发点），
  /// 返回本帧是否发生了击毁翻转
  bool _applyTankTarget(TankPlayer player, TankNetTankState state) {
    final tank = _host.tank(player);
    if (tank == null) return false; // 素材未加载完成（onLoad 前），跳过待下帧
    var destroyedNow = false;
    if (state.destroyed && !tank.destroyed) {
      tank.destroyed = true;
      _host.spawnExplosion(player);
      destroyedNow = true;
    } else if (!state.destroyed && tank.destroyed) {
      // 击毁→复活仅出现在新回合（TCP 按序下先收 roundStart 复位，
      // 此处为快照先于回合消息的时序兜底）
      tank.destroyed = false;
    }
    final target = Vector2(state.x, state.y);
    // 差分估计速度（EMA 平滑滤网络抖动）：间隔异常（首快照/断流后恢复）
    // 或超极速时不更新，沿用上次估计（限幅保证外推不会快过真实坦克）
    final now = _nowSec();
    final last = _lastTargetTime[player];
    final prev = _tankTargets[player];
    if (last != null && prev != null) {
      final dt = now - last;
      if (dt > 0.005 && dt < 0.5) {
        final v = (target - prev.$1) / dt;
        final capped = v.length <= Tank.maxForwardSpeed
            ? v
            : (v / v.length) * Tank.maxForwardSpeed;
        final old = _tankVelocities[player];
        _tankVelocities[player] =
            old == null ? capped : old + (capped - old) * 0.5;
      }
    }
    _lastTargetTime[player] = now;
    _tankTargets[player] = (target, state.angle);
    return destroyedNow;
  }

  /// 每帧准备：计算本帧快照年龄并写入全部远程子弹。
  /// 必须先于宿主推进子组件调用，顺序颠倒会让子弹用到上一帧的年龄，
  /// 产生恒定一帧的渲染滞后。
  /// 冻结期语义是全场精确定格：快照位置静止而年龄持续增长会让外推
  /// 把坦克/子弹推到快照位置前方，故冻结期年龄视为 0（不做外推）
  void beginFrame() {
    _frameAge = _phase == TankBattlePhase.frozen
        ? 0.0
        : math.min(_nowSec() - _lastSnapshotAt, _maxExtrapolateAge);
    for (final bullet in _remoteBullets.values) {
      bullet.snapshotAge = _frameAge;
    }
  }

  /// 坦克渲染平滑：朝按年龄外推的移动目标指数逼近（位置 + 最短弧朝向）。
  /// 击毁的坦克跳过（隐身由渲染同步缩放归零处理）。
  /// 年龄取 [beginFrame] 写入的本帧值
  void smoothTanks(double dt) {
    final t = 1 - math.exp(-_remoteSmoothK * dt);
    for (final entry in _tankTargets.entries) {
      final tank = _host.tank(entry.key);
      if (tank == null || tank.destroyed) continue;
      final (target, targetAngle) = entry.value;
      // 渲染目标 = 快照位置 + 估计速度 × 快照年龄：快照晚到/间隔抖动时
      // 目标持续前进，坦克不再"追上即停"（卡顿感根源）；
      // 匀速假设下目标连续（快照位置本身按同速前进），无跳变
      final v = _tankVelocities[entry.key];
      final projected = v == null ? target : target + v * _frameAge;
      tank.logicalPos += (projected - tank.logicalPos) * t;
      tank.angle += Tank.angleDelta(tank.angle, targetAngle) * t;
    }
  }

  /// 新回合战场复位：清空全部远程子弹与平滑/外推状态。
  /// 由宿主重建战场（换迷宫/坦克复位/清场）时联动调用——
  /// 旧目标/估计速度不清会把复位的坦克立即推离出生点
  /// （新局快照到达前坦克应停在出生点）
  void resetState() {
    for (final bullet in _remoteBullets.values) {
      bullet.removeFromParent();
    }
    _remoteBullets.clear();
    _tankTargets.clear();
    _tankVelocities.clear();
    _lastTargetTime.clear();
    _lastSnapshotAt = 0;
    _frameAge = 0;
  }

  /// 远程子弹渲染坐标同步（中心像素位置 + 单元格缩放），
  /// 由宿主战场渲染同步时一并调用——漏掉这组同步会让子弹停在原点
  /// 且只有逻辑尺寸（肉眼不可见）
  void syncBullets() {
    for (final bullet in _remoteBullets.values) {
      bullet
        ..position = _host.logicalToScreen(bullet.logicalPos)
        ..scale = Vector2.all(_host.cell);
    }
  }

  /// 当前墙钟（秒）
  static double _nowSec() => DateTime.now().microsecondsSinceEpoch / 1e6;
}

/// 远程子弹：纯渲染组件（不参与本地物理与碰撞），位置由状态快照驱动。
/// 渲染平滑：目标 = 快照位置沿飞行方向按快照年龄外推（真实速度），
/// 每帧以 [Bullet.speed] 匀速推进——快照晚到时目标持续前进不停滞，
/// 反弹折点呈短弧过渡；快照间隔短时两者几乎重合。
/// 音效：快照朝向突变即房主侧发生反弹（直线飞行朝向恒定），
/// 客户端无本地物理，撞墙声只能据此推断补播
class _RemoteBullet extends PositionComponent {
  /// 反弹判定阈值（弧度）：掠射反弹的方向变化为入射角的 2 倍，
  /// 阈值覆盖入射角 3° 以上的反弹；更贴墙的滑行极罕见，漏一声可接受
  static const double _bounceAngleThreshold = 0.1;

  _RemoteBullet({
    required Sprite sprite,
    required Color color,
    required Vector2 logicalPos,
    required this.heading,
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

  /// 当前飞行朝向（快照写入，弧度）：反弹检测与外推方向依据
  double heading;

  /// 快照年龄（秒，战场每帧写入，含断流上限）：目标位置沿飞行方向
  /// 按年龄外推——快照晚到/间隔抖动时子弹持续推进，不再飞到快照
  /// 位置就停滞等下一条快照（卡顿感根源）
  double snapshotAge = 0;

  /// 快照更新平滑目标；朝向突变（最短角差超阈值）补播撞墙音效
  void retarget(double x, double y, double angle) {
    if (Tank.angleDelta(heading, angle).abs() > _bounceAngleThreshold) {
      TankAudio.wallBounce();
    }
    heading = angle;
    _target = Vector2(x, y);
  }

  @override
  void update(double dt) {
    super.update(dt);
    // 渲染目标 = 快照位置 + 飞行方向 × 真实速度 × 快照年龄；
    // 匀速假设下目标随时间连续前移，推进保持匀速无锯齿
    final dir = Vector2(math.cos(heading), math.sin(heading));
    final projected = _target + dir * (Bullet.speed * snapshotAge);
    final delta = projected - logicalPos;
    final dist = delta.length;
    if (dist <= 1e-6) return;
    final step = math.min(Bullet.speed * dt, dist);
    logicalPos += delta * (step / dist);
  }
}
