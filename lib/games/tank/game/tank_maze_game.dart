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

/// 坦克动荡战场游戏（Flame）：渲染每局随机生成的迷宫，并驱动坦克实体。
/// 迷宫按画布尺寸等比缩放并居中；墙体参数取自原版截图实测。
/// 坦克状态存于迷宫坐标系（与画布尺寸无关）：画布尺寸变化（进对局页的
/// 横屏旋转、前后台切换）只重建迷宫渲染并重新换算坦克渲染坐标，
/// 坦克位置与朝向不丢失；仅新生成迷宫（新对局）时回到出生点。
class TankMazeGame extends FlameGame {
  TankMazeGame({required this.maze}) {
    _rebuildLogicalWalls();
  }

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
  /// 已击毁的坦克忽略输入（战果展示期内存活坦克仍可正常驾驶）
  void setDrive(TankPlayer player, TankDriveInput? input) {
    _tanks[player]?.input = input;
  }

  /// 开火：从炮口沿车身朝向射出子弹。
  /// 每辆坦克同屏最多 5 发：达到上限后需等任一子弹消失才能继续发射。
  /// 已击毁的坦克不能再开火
  void fire(TankPlayer player) {
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
  /// 战场继续 2.5 秒（残弹可继续反弹与命中，双杀可能发生），
  /// 到点结算计分（存活方得分；双杀无人得分）→ 冻结 0.5 秒 → 开新一局
  void _onTankDestroyed(TankPlayer victim) {
    TankAudio.explosion();
    _tanks[victim]!
      ..destroyed = true
      ..input = null;

    // 在爆点叠加爆炸特效：position 为上帧同步的屏幕坐标（击毁瞬间即最终位置）。
    // 特效为纯渲染叠加组件，不参与碰撞，不影响子弹/坦克逻辑。
    // 尺寸换算：素材坐标中坦克体长 48pt，本战场坦克缩放为 _cell 像素（scale=_cell），
    // 粒子参数（pt）乘 _cell/48 才能与坦克保持一致的比例观感
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

    _roundOver = true;
    _settleCountdown = _roundSettleDelay;
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
    maze = TankMaze.generate();
    _rebuildLogicalWalls();
    if (_lastCanvasSize != null) _buildMaze(_lastCanvasSize!);
    _resetTanks();
    _clearBullets();
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
