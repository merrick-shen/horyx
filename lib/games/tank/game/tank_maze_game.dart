import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:horyx/games/tank/game/tank.dart';
import 'package:horyx/games/tank/models/tank_maze.dart';
import 'package:horyx/games/tank/models/tank_player.dart';

/// 坦克动荡战场游戏（Flame）：渲染每局随机生成的迷宫，并驱动坦克实体。
/// 迷宫按画布尺寸等比缩放并居中；墙体参数取自原版截图实测。
/// 坦克状态存于迷宫坐标系（与画布尺寸无关）：画布尺寸变化（进对局页的
/// 横屏旋转、前后台切换）只重建迷宫渲染并重新换算坦克渲染坐标，
/// 坦克位置与朝向不丢失；仅新生成迷宫（新对局）时回到出生点。
class TankMazeGame extends FlameGame {
  TankMazeGame({required this.maze}) {
    // 迷宫碰撞数据（逻辑单位=格）：与画布尺寸无关，构建一次即可。
    // 墙段两端各延伸半个墙厚（0.05 格）覆盖转角接缝，与渲染一致
    _logicalWalls = [
      for (final (x, y, vertical) in maze.walls)
        vertical
            ? Rect.fromLTWH(x - 0.05, y - 0.05, 0.10, 1.10)
            : Rect.fromLTWH(x - 0.05, y - 0.05, 1.10, 0.10),
    ];
  }

  /// 本局迷宫
  final TankMaze maze;

  /// 双方坦克（按玩家索引，供摇杆输入下发）
  final Map<TankPlayer, Tank> _tanks = {};

  /// 已构建的迷宫组件（画布尺寸变化时先清空再重建）
  final List<Component> _mazeComponents = [];

  /// 墙体碰撞矩形（迷宫单位）
  late final List<Rect> _logicalWalls;

  /// 画布几何：单元格边长（像素）与迷宫左上角偏移（渲染换算用）
  double _cell = 0;
  Vector2 _boardOffset = Vector2.zero();

  /// 坦克白模素材（onLoad 异步加载，加载完成前不出生坦克）
  Sprite? _bodySprite;
  Sprite? _cannonSprite;

  /// 画布透明：迷宫底板直接铺在对局页背景色上，
  /// 与原版一致（迷宫面板比页面底色略深一层）
  @override
  Color backgroundColor() => const Color(0x00000000);

  /// 对局页摇杆驾驶输入下发（player 对应的坦克执行转向/前进）
  void setDrive(TankPlayer player, TankDriveInput? input) {
    _tanks[player]?.input = input;
  }

  // onGameResize 在首次挂载与每次画布尺寸变化时都会调用。
  // 对局页强制横屏的旋转过程中画布尺寸会突变，布局必须按最新尺寸重建，
  // 否则迷宫停留在旧尺寸坐标系里（表现为过小且偏离中心）
  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (size.x <= 0 || size.y <= 0) return;
    _buildMaze(size);
    _ensureTanks();
    _syncTanks();
  }

  @override
  Future<void> onLoad() async {
    _bodySprite = Sprite(await _loadImage('assets/tank/tank_body.png'));
    _cannonSprite = Sprite(await _loadImage('assets/tank/tank_cannon.png'));
    _ensureTanks();
    _syncTanks();
  }

  @override
  void update(double dt) {
    // 先让坦克推进迷宫坐标系状态，再按最新状态同步渲染坐标
    super.update(dt);
    _syncTanks();
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

  /// 把坦克逻辑状态换算为渲染坐标（中心像素位置 + 单元格缩放）
  void _syncTanks() {
    if (_cell == 0) return;
    for (final tank in _tanks.values) {
      tank
        ..position = _boardOffset + tank.logicalPos * _cell
        ..scale = Vector2.all(_cell);
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
