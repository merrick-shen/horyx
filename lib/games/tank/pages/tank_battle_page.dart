import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:horyx/games/tank/game/tank_maze_game.dart';
import 'package:horyx/games/tank/models/tank_maze.dart';
import 'package:horyx/games/tank/models/tank_player.dart';
import 'package:horyx/games/tank/widgets/tank_fire_button.dart';
import 'package:horyx/games/tank/widgets/tank_joystick.dart';
import 'package:horyx/games/tank/widgets/tank_score_view.dart';
import 'package:horyx/shared/theme/app_theme.dart';

/// 坦克动荡本地对局页（横屏全屏，无顶栏）
/// 布局复刻原版截图：两列控制呈中心对称，中间为战场区域，适合手机平放桌面对坐——
/// - 左列（自上而下）：绿方开火钮 / 红方比分 / 红方摇杆
/// - 右列（自上而下）：绿方摇杆 / 绿方比分 / 红方开火钮
/// 本阶段完成比分、摇杆与开火钮的界面交互；开火回调与坦克移动逻辑
/// 随战场（迷宫）实现接入，摇杆方向先记录在 [_directions]
class TankBattlePage extends StatefulWidget {
  const TankBattlePage({super.key});

  @override
  State<TankBattlePage> createState() => _TankBattlePageState();
}

class _TankBattlePageState extends State<TankBattlePage> {
  /// 双方比分（对局胜负逻辑接入前恒为 0，先行展示布局；接入时改为可变）
  final int _redScore = 0;
  final int _greenScore = 0;

  /// 双方当前摇杆方向；null 表示摇杆回中
  final Map<TankPlayer, TankMoveDirection?> _directions = {
    TankPlayer.red: null,
    TankPlayer.green: null,
  };

  /// 战场游戏（Flame）：每进入对局页生成一局随机迷宫并渲染；
  /// 坦克、子弹等实体后续接入该游戏循环
  late final TankMazeGame _game = TankMazeGame(maze: TankMaze.generate());

  @override
  void initState() {
    super.initState();
    // 对局页强制横屏 + 沉浸式（隐藏状态栏/导航栏），退出页面时在 dispose 还原
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onDirection(TankPlayer player, TankMoveDirection? direction) {
    _directions[player] = direction;
  }

  /// 开火回调占位：子弹发射随战场实现接入
  void _onFire() {}

  @override
  Widget build(BuildContext context) {
    // 对局暂无存档：系统返回直接退出对局页，
    // 退出确认弹窗待对局存档功能实现后再接入
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      // 不用 SafeArea：横屏挖孔/刘海只在一侧产生 inset，
      // 两侧取较大避让值才能保证左右操作区到屏幕边缘的距离完全对称
      body: LayoutBuilder(
        builder: (context, constraints) {
          final insets = MediaQuery.of(context).padding;
          final hCutout =
              insets.left > insets.right ? insets.left : insets.right;
          // 三行等高槽位随屏幕高度收缩（下限 104 防控件过小），
          // 避免固定槽高在小屏横屏下纵向溢出
          final slotHeight = math
              .max(104.0, math.min(140.0, (constraints.maxHeight - 32) / 3));
          return Padding(
            padding: EdgeInsets.fromLTRB(hCutout, 0, hCutout, 0),
            child: Row(
              children: [
                _buildLeftColumn(slotHeight),
                // 战场区域：Flame 画布渲染本局迷宫
                Expanded(child: GameWidget(game: _game)),
                _buildRightColumn(slotHeight),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 等高槽位：较小控件（开火钮/比分）在槽内居中
  Widget _slot(double height, Widget child) => SizedBox(
        height: height,
        child: Center(child: child),
      );

  /// 左列控制：绿方开火钮 / 红方比分 / 红方摇杆（复刻原版交叉布局）
  Widget _buildLeftColumn(double slotHeight) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _slot(
            slotHeight,
            TankFireButton(color: TankPlayer.green.color, onTap: _onFire),
          ),
          _slot(
            slotHeight,
            TankScoreView(player: TankPlayer.red, score: _redScore),
          ),
          TankJoystick(
            color: TankPlayer.red.color,
            size: slotHeight,
            onDirection: (d) => _onDirection(TankPlayer.red, d),
          ),
        ],
      ),
    );
  }

  /// 右列控制：绿方摇杆 / 绿方比分 / 红方开火钮
  /// 结构与左列完全一致（仅控件种类镜像），保证两列宽度与行位置对称
  Widget _buildRightColumn(double slotHeight) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TankJoystick(
            color: TankPlayer.green.color,
            size: slotHeight,
            onDirection: (d) => _onDirection(TankPlayer.green, d),
          ),
          _slot(
            slotHeight,
            TankScoreView(
              player: TankPlayer.green,
              score: _greenScore,
              mirrored: true,
            ),
          ),
          _slot(
            slotHeight,
            TankFireButton(color: TankPlayer.red.color, onTap: _onFire),
          ),
        ],
      ),
    );
  }
}
