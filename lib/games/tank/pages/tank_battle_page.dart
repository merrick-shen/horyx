import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'package:horyx/games/tank/engine/tank_maze_game.dart';
import 'package:horyx/games/tank/models/tank_game_state.dart';
import 'package:horyx/games/tank/models/tank_maze.dart';
import 'package:horyx/games/tank/models/tank_player.dart';
import 'package:horyx/games/tank/widgets/tank_control_column.dart';
import 'package:horyx/games/tank/widgets/tank_fire_button.dart';
import 'package:horyx/games/tank/widgets/tank_joystick.dart';
import 'package:horyx/games/tank/widgets/tank_score_view.dart';
import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/utils/landscape_immersive_mixin.dart';
import 'package:horyx/shared/widgets/confirm_dialog.dart';

/// 坦克动荡本地对局页（横屏全屏，无顶栏）
/// 布局复刻原版截图：两列控制呈中心对称，中间为战场区域，适合手机平放桌面对坐——
/// - 左列（自上而下）：绿方开火钮 / 红方比分 / 红方摇杆
/// - 右列（自上而下）：绿方摇杆 / 绿方比分 / 红方开火钮
/// 退出时按当前比分询问存档（仅保存比分；坦克位置、地图等战场状态不保存），
/// 恢复对战时从存档比分继续累计，战场重开一局随机迷宫
class TankBattlePage extends StatefulWidget {
  const TankBattlePage({
    super.key,
    this.initialRedScore = 0,
    this.initialGreenScore = 0,
    required this.onSave,
  });

  /// 初始比分（从存档恢复对战时传入，新对局默认 0:0）
  final int initialRedScore;
  final int initialGreenScore;

  /// 保存当前比分：由父级设置页（TankPage）注入——存档绑定与覆盖语义
  /// 统一由其基类管理，本页只组装状态模型；返回 Future 以等待写盘完成
  final Future<void> Function(TankGameState) onSave;

  @override
  State<TankBattlePage> createState() => _TankBattlePageState();
}

class _TankBattlePageState extends State<TankBattlePage>
    with LandscapeImmersiveMixin {
  /// 双方比分（由战场游戏的得分回调驱动刷新）
  late int _redScore = widget.initialRedScore;
  late int _greenScore = widget.initialGreenScore;

  /// 双方得分烟雾触发计数（每次得分自增，驱动数字上的烟雾特效）
  int _redSmokeTick = 0;
  int _greenSmokeTick = 0;

  /// 战场游戏（Flame）：每进入对局页生成一局随机迷宫并渲染
  late final TankMazeGame _game = TankMazeGame(maze: TankMaze.generate());

  @override
  void initState() {
    super.initState();
    // 对局页强制横屏 + 沉浸式（隐藏状态栏/导航栏），退出还原由 mixin 兜底
    enterLandscapeImmersive();
    // 战场得分回调：刷新比分 UI；
    // 恢复对战时把存档比分同步给战场（战场内部计分从该值继续累计）
    _game
      ..redScore = widget.initialRedScore
      ..greenScore = widget.initialGreenScore;
    _game.onScored = _onScored;
  }

  /// 得分回调（战场游戏在坦克被击毁时触发）：
  /// 数字变化与烟雾特效同时出现
  void _onScored(TankPlayer player) {
    setState(() {
      if (player == TankPlayer.red) {
        _redScore++;
        _redSmokeTick++;
      } else {
        _greenScore++;
        _greenSmokeTick++;
      }
    });
  }

  void _onDrive(TankPlayer player, TankDriveInput? input) {
    // 驾驶输入实时下发战场游戏，驱动对应坦克转向/前进
    _game.setDrive(player, input);
  }

  /// 开火：下发战场游戏（炮口沿车身朝向射出子弹，同屏上限 5 发）
  void _onFire(TankPlayer player) => _game.fire(player);

  /// 退出到设置页（TankPage）：先发起竖屏与 UI 模式恢复、再 pop——
  /// 系统旋转与转场动画并行执行；若等转场结束（dispose）才开始旋转，
  /// 两个耗时串行叠加，退出后要明显多等约半秒才回到竖屏。
  /// （dispose 的还原由 mixin 兜底，覆盖未经本方法的 pop 路径）。
  /// 仅用于比分与进入时相同（无进行中内容）的直接退出
  /// （与其他游戏开局无操作回设置视图一致）
  void _exitToSetup() {
    restorePortrait();
    Navigator.of(context).pop();
  }

  /// 退出到主页：保存/不保存退出的目的地与其他游戏一致——
  /// 连设置页一并关闭，直接返回主页（popUntil 到根路由）
  void _exitToHome() {
    restorePortrait();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// 退出对局请求：比分与进入时相同（未得分，含恢复存档后未推动进度）
  /// 时无进行中内容，直接返回设置页且不动存档（原样保留，下次仍可恢复）；
  /// 否则弹三选项确认（保存并退出 / 不保存并退出 / 取消），
  /// 确认后的保存/不保存均退出整页回主页（与其他游戏统一）。
  /// 仅保存比分——坦克位置、地图等战场状态本就不跨局保留，无需存档
  Future<void> _requestExit() async {
    if (_redScore == widget.initialRedScore &&
        _greenScore == widget.initialGreenScore) {
      _exitToSetup();
      return;
    }

    await confirmExitWithArchive(
      this,
      onSave: () => widget.onSave(
        TankGameState(
          redScore: _redScore,
          greenScore: _greenScore,
          savedAt: DateTime.now(),
        ),
      ),
      onExit: _exitToHome,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 拦截系统返回走退出确认流程（保存/不保存/取消）
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestExit();
      },
      child: Scaffold(
        backgroundColor: context.palette.scaffoldBg,
        // 不用 SafeArea：横屏挖孔/刘海只在一侧产生 inset，
        // 两侧取较大避让值才能保证左右操作区到屏幕边缘的距离完全对称
        body: LayoutBuilder(
          builder: (context, constraints) {
            final insets = MediaQuery.of(context).padding;
            final hCutout = math.max(insets.left, insets.right);
            final slotHeight =
                TankControlColumn.slotHeightFor(constraints.maxHeight);
            return Padding(
              padding: EdgeInsets.fromLTRB(hCutout, 0, hCutout, 0),
              child: Row(
                children: [
                  // 左列（自上而下）：绿方开火钮 / 红方比分 / 红方摇杆（复刻原版交叉布局）
                  TankControlColumn(
                    slotHeight: slotHeight,
                    top: TankFireButton(
                      color: TankPlayer.green.color,
                      onTap: () => _onFire(TankPlayer.green),
                    ),
                    middle: TankScoreView.smoke(
                      player: TankPlayer.red,
                      score: _redScore,
                      smokeTick: _redSmokeTick,
                    ),
                    bottom: TankJoystick(
                      color: TankPlayer.red.color,
                      size: slotHeight,
                      onDrive: (input) => _onDrive(TankPlayer.red, input),
                    ),
                  ),
                  // 战场区域：Flame 画布渲染本局迷宫
                  Expanded(child: GameWidget(game: _game)),
                  // 右列（自上而下）：绿方摇杆 / 绿方比分 / 红方开火钮
                  TankControlColumn(
                    slotHeight: slotHeight,
                    top: TankJoystick(
                      color: TankPlayer.green.color,
                      size: slotHeight,
                      onDrive: (input) => _onDrive(TankPlayer.green, input),
                    ),
                    middle: TankScoreView.smoke(
                      player: TankPlayer.green,
                      score: _greenScore,
                      smokeTick: _greenSmokeTick,
                      mirrored: true,
                    ),
                    bottom: TankFireButton(
                      color: TankPlayer.red.color,
                      onTap: () => _onFire(TankPlayer.red),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
