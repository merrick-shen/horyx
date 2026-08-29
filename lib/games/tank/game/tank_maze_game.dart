import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'package:horyx/games/tank/models/tank_maze.dart';

/// 坦克动荡战场游戏（Flame）：本阶段渲染每局随机生成的迷宫，
/// 坦克、子弹等实体与游戏循环逻辑后续接入。
/// 迷宫按画布尺寸等比缩放并居中；墙体参数取自原版截图实测。
class TankMazeGame extends FlameGame {
  TankMazeGame({required this.maze});

  /// 本局迷宫
  final TankMaze maze;

  /// 已构建的迷宫组件（画布尺寸变化时先清空再重建）
  final List<Component> _mazeComponents = [];

  /// 画布透明：迷宫底板直接铺在对局页背景色上，
  /// 与原版一致（迷宫面板比页面底色略深一层）
  @override
  Color backgroundColor() => const Color(0x00000000);

  // onGameResize 在首次挂载与每次画布尺寸变化时都会调用。
  // 对局页强制横屏的旋转过程中画布尺寸会突变，布局必须按最新尺寸重建，
  // 否则迷宫停留在旧尺寸坐标系里（表现为过小且偏离中心）
  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (size.x <= 0 || size.y <= 0) return;
    _buildMaze(size);
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
      _add(
        vertical
            ? RectangleComponent(
                position: Vector2(
                  offsetX + x * cell - thickness / 2,
                  offsetY + y * cell - thickness / 2,
                ),
                size: Vector2(thickness, cell + thickness),
                paint: wallPaint,
              )
            : RectangleComponent(
                position: Vector2(
                  offsetX + x * cell - thickness / 2,
                  offsetY + y * cell - thickness / 2,
                ),
                size: Vector2(cell + thickness, thickness),
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
