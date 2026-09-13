import 'dart:math' as math;

import 'package:horyx/games/tank/models/tank_battle_phase.dart';
import 'package:horyx/games/tank/models/tank_player.dart';
import 'package:horyx/shared/network/net_message.dart';

/// 坦克动荡联机消息的编解码层（纯数据，不做任何模拟/渲染）
///
/// 协议分工（房主权威模型，见 tank_online_plan.md）：
/// - 房主本地跑完整模拟，30Hz 广播 [TankNetSnapshot] 状态快照；
/// - 客户端只上报驾驶/开火输入，影子战场按快照驱动渲染；
/// - 迷宫一致性靠 [TankNetRoundStart] 的随机种子：双端以
///   `Random(seed)` 生成同一迷宫，无需传输墙体数据；
/// - 开火音效走 [NetMessageType.tankFireEvent] 即时事件，
///   不等 30Hz 快照（子弹本体仍由快照承载）。
///
/// 所有解码函数对载荷做类型校验：字段缺失/类型不符一律返回 null，
/// 由调用方丢弃该消息（同版本协议下不应发生，防御异常/篡改载荷）。
/// 快照 30Hz 传输，载荷键名取短名控制报文体积。

/// 单辆坦克的快照状态（迷宫坐标系，单位=格，与本地实体一致）
class TankNetTankState {
  const TankNetTankState({
    required this.x,
    required this.y,
    required this.angle,
    required this.destroyed,
  });

  /// 车体中心位置（迷宫坐标，格）
  final double x;
  final double y;

  /// 车身朝向（弧度，0 朝右、y 向下顺时针为正）
  final double angle;

  /// 是否已被击毁（击毁后隐身冻结，客户端不再渲染）
  final bool destroyed;

  /// 编码为快照载荷中的坦克条目
  Map<String, dynamic> toPayload() =>
      {'x': x, 'y': y, 'a': angle, 'dead': destroyed};

  /// 从快照载荷解码坦克条目；结构不符返回 null
  static TankNetTankState? fromPayload(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final x = raw['x'];
    final y = raw['y'];
    final a = raw['a'];
    final dead = raw['dead'];
    if (x is! num || y is! num || a is! num || dead is! bool) return null;
    return TankNetTankState(
      x: x.toDouble(),
      y: y.toDouble(),
      angle: a.toDouble(),
      destroyed: dead,
    );
  }
}

/// 单颗子弹的快照状态
class TankNetBulletState {
  const TankNetBulletState({
    required this.id,
    required this.owner,
    required this.x,
    required this.y,
    required this.angle,
  });

  /// 子弹标识（房主自增分配）：客户端按 id 匹配既有子弹做平滑，
  /// 避免快照间列表顺序变化导致渲染跳变
  final int id;

  /// 发射方（子弹染色与归属坦克一致）
  final TankPlayer owner;

  /// 子弹中心位置（迷宫坐标，格）
  final double x;
  final double y;

  /// 飞行朝向（弧度）
  final double angle;

  /// 编码为快照载荷中的子弹条目
  Map<String, dynamic> toPayload() =>
      {'id': id, 'o': owner.name, 'x': x, 'y': y, 'a': angle};

  /// 从快照载荷解码子弹条目；结构不符返回 null
  static TankNetBulletState? fromPayload(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id'];
    final owner = TankPlayer.values.asNameMap()[raw['o']];
    final x = raw['x'];
    final y = raw['y'];
    final a = raw['a'];
    if (id is! int || owner == null) return null;
    if (x is! num || y is! num || a is! num) return null;
    return TankNetBulletState(
      id: id,
      owner: owner,
      x: x.toDouble(),
      y: y.toDouble(),
      angle: a.toDouble(),
    );
  }
}

/// 整个战场的状态快照（房主 30Hz 广播）
class TankNetSnapshot {
  const TankNetSnapshot({
    required this.redScore,
    required this.greenScore,
    required this.phase,
    required this.redTank,
    required this.greenTank,
    required this.bullets,
  });

  /// 双方比分（红=座位 1 房主，绿=座位 2 客户端）
  final int redScore;
  final int greenScore;

  /// 战场阶段
  final TankBattlePhase phase;

  /// 双方坦克状态（键缺失视为载荷损坏，整体丢弃）
  final TankNetTankState redTank;
  final TankNetTankState greenTank;

  /// 全部在场子弹（房主权威全量列表）
  final List<TankNetBulletState> bullets;

  /// 编码为快照消息
  NetMessage toMessage() => NetMessage(
        type: NetMessageType.tankSnapshot,
        payload: {
          'score': [redScore, greenScore],
          'phase': phase.toPayload(),
          'red': redTank.toPayload(),
          'green': greenTank.toPayload(),
          'bullets': [for (final b in bullets) b.toPayload()],
        },
      );

  /// 从快照消息解码；载荷损坏（坦克缺失/比分非法）返回 null
  static TankNetSnapshot? fromMessage(NetMessage message) {
    final p = message.payload;
    final score = p['score'];
    final redTank = TankNetTankState.fromPayload(p['red']);
    final greenTank = TankNetTankState.fromPayload(p['green']);
    final phase = TankBattlePhase.tryParse(p['phase']);
    if (score is! List ||
        score.length != 2 ||
        score[0] is! int ||
        score[1] is! int) {
      return null;
    }
    if (redTank == null || greenTank == null || phase == null) return null;
    final rawBullets = p['bullets'];
    if (rawBullets is! List) return null;
    final bullets = <TankNetBulletState>[];
    for (final raw in rawBullets) {
      final bullet = TankNetBulletState.fromPayload(raw);
      if (bullet == null) return null; // 任一颗子弹损坏即整体丢弃
      bullets.add(bullet);
    }
    return TankNetSnapshot(
      redScore: score[0] as int,
      greenScore: score[1] as int,
      phase: phase,
      redTank: redTank,
      greenTank: greenTank,
      bullets: bullets,
    );
  }
}

/// 回合开始消息（房主开新迷宫时广播）：双端以同种子重建迷宫
class TankNetRoundStart {
  const TankNetRoundStart({
    required this.seed,
    required this.cols,
    required this.rows,
    required this.redScore,
    required this.greenScore,
  });

  /// 迷宫随机种子：双端 `Random(seed)` 生成同一迷宫；
  /// 取 31 位正整数避免 JSON 序列化时出现浮点化风险
  final int seed;

  /// 迷宫规格（格）
  final int cols;
  final int rows;

  /// 开新局时的双方比分
  final int redScore;
  final int greenScore;

  /// 编码为回合开始消息
  NetMessage toMessage() => NetMessage(
        type: NetMessageType.tankRoundStart,
        payload: {
          'seed': seed,
          'cols': cols,
          'rows': rows,
          'red': redScore,
          'green': greenScore,
        },
      );

  /// 从回合开始消息解码；规格非法返回 null（迷宫必须有正数网格）
  static TankNetRoundStart? fromMessage(NetMessage message) {
    final p = message.payload;
    final seed = p['seed'];
    final cols = p['cols'];
    final rows = p['rows'];
    final red = p['red'];
    final green = p['green'];
    if (seed is! int ||
        cols is! int ||
        rows is! int ||
        red is! int ||
        green is! int) {
      return null;
    }
    if (cols < 1 || rows < 1) return null;
    return TankNetRoundStart(
      seed: seed,
      cols: cols,
      rows: rows,
      redScore: red,
      greenScore: green,
    );
  }
}

/// 构造驾驶输入消息：客户端 → 房主。
/// [input] 为 null 表示摇杆归位（angle 字段为 JSON null），与
/// 「圆钮在底座内」的原地转向输入（speed 0 但带角度）严格区分——
/// 前者停车，后者只转向不前进（原版操控语义，见 TankJoystick）；
/// 角度按 2π 归一为 [0, 2π)，避免负角度浮点在 JSON 中的冗余表示
NetMessage tankDriveMessage(TankDriveInput? input) => NetMessage(
      type: NetMessageType.tankDrive,
      payload: {
        'angle':
            input == null ? null : input.targetAngle % (2 * math.pi),
        'speed': input?.speedFactor ?? 0.0,
      },
    );

/// 从驾驶输入消息解码；speed 非法（负数/超 1）或 angle 缺失（摇杆归位）
/// 返回 null，调用方统一按停车处理；带角度的 speed 0 = 原地转向（只转不走）
TankDriveInput? parseTankDrive(NetMessage message) {
  final p = message.payload;
  final angle = p['angle'];
  final speed = p['speed'];
  if (speed is! num) return null;
  final s = speed.toDouble();
  if (s < 0 || s > 1) return null;
  if (angle == null) return null;
  if (angle is! num) return null;
  return TankDriveInput(
    targetAngle: angle.toDouble(),
    speedFactor: s,
  );
}

/// 构造开火请求消息：客户端 → 房主（无载荷）
NetMessage tankFireMessage() =>
    const NetMessage(type: NetMessageType.tankFire);

/// 构造开火事件消息：房主 → 客户端（即时音效用）
NetMessage tankFireEventMessage(TankPlayer owner) => NetMessage(
      type: NetMessageType.tankFireEvent,
      payload: {'owner': owner.name},
    );

/// 从开火事件消息解码开火方；载荷损坏返回 null
TankPlayer? parseTankFireEvent(NetMessage message) =>
    TankPlayer.values.asNameMap()[message.payload['owner']];
