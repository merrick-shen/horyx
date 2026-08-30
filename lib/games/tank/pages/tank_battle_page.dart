import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:horyx/games/tank/game/tank_maze_game.dart';
import 'package:horyx/games/tank/models/tank_game_state.dart';
import 'package:horyx/games/tank/models/tank_maze.dart';
import 'package:horyx/games/tank/models/tank_player.dart';
import 'package:horyx/games/tank/services/tank_storage.dart';
import 'package:horyx/games/tank/widgets/score_smoke_effect.dart';
import 'package:horyx/games/tank/widgets/tank_fire_button.dart';
import 'package:horyx/games/tank/widgets/tank_joystick.dart';
import 'package:horyx/games/tank/widgets/tank_score_view.dart';
import 'package:horyx/shared/theme/app_theme.dart';
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
  });

  /// 初始比分（从存档恢复对战时传入，新对局默认 0:0）
  final int initialRedScore;
  final int initialGreenScore;

  @override
  State<TankBattlePage> createState() => _TankBattlePageState();
}

class _TankBattlePageState extends State<TankBattlePage> {
  /// 双方比分（由战场游戏的得分回调驱动刷新）
  late int _redScore = widget.initialRedScore;
  late int _greenScore = widget.initialGreenScore;

  /// 双方得分烟雾触发计数（每次得分自增，驱动数字上的烟雾特效）
  int _redSmokeTick = 0;
  int _greenSmokeTick = 0;

  /// 双方当前摇杆驾驶输入；null 表示摇杆回中（停车）
  final Map<TankPlayer, TankDriveInput?> _driveInputs = {
    TankPlayer.red: null,
    TankPlayer.green: null,
  };

  /// 战场游戏（Flame）：每进入对局页生成一局随机迷宫并渲染
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

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onDrive(TankPlayer player, TankDriveInput? input) {
    _driveInputs[player] = input;
    // 驾驶输入实时下发战场游戏，驱动对应坦克转向/前进
    _game.setDrive(player, input);
  }

  /// 开火：下发战场游戏（炮口沿车身朝向射出子弹，同屏上限 5 发）
  void _onFire(TankPlayer player) => _game.fire(player);

  /// 退出对局请求：比分 0:0 时无进行中内容，直接返回设置页；
  /// 否则弹三选项确认（保存并退出 / 不保存并退出 / 取消）。
  /// 仅保存比分——坦克位置、地图等战场状态本就不跨局保留，无需存档
  Future<void> _requestExit() async {
    if (_redScore == 0 && _greenScore == 0) {
      Navigator.of(context).pop();
      return;
    }

    await confirmExitWithArchive(
      this,
      title: '退出对战？',
      message: '保存并退出后，下次进入可从当前比分继续',
      onSave: () => TankStorage.instance.save(
        TankGameState(
          redScore: _redScore,
          greenScore: _greenScore,
          savedAt: DateTime.now(),
        ),
      ),
      onDiscard: TankStorage.instance.clear,
      onExit: () => Navigator.of(context).pop(),
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
            final hCutout =
                insets.left > insets.right ? insets.left : insets.right;
            // 三行等高槽位随屏幕高度收缩（下限 104 防控件过小），
            // 避免固定槽高在小屏横屏下纵向溢出；
            // 80 = 摇杆列上下留白（_panelPadding）×2
            final slotHeight = math.max(
                104.0, math.min(140.0, (constraints.maxHeight - 80) / 3));
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
      ),
    );
  }

  /// 摇杆列四周留白：圆钮推出底座时会越过摇杆区域约半个钮径
  /// （最大约槽高 12%+，140 槽时约 34px），留白必须覆盖之——
  /// 否则左侧圆钮会被后绘制的地图区盖住、下方会伸出屏幕外
  static const double _panelPadding = 40;

  /// 等高槽位：较小控件（开火钮/比分）在槽内居中
  Widget _slot(double height, Widget child) => SizedBox(
        height: height,
        child: Center(child: child),
      );

  /// 左列控制：绿方开火钮 / 红方比分 / 红方摇杆（复刻原版交叉布局）
  Widget _buildLeftColumn(double slotHeight) {
    return Padding(
      padding: const EdgeInsets.all(_panelPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _slot(
            slotHeight,
            TankFireButton(
              color: TankPlayer.green.color,
              onTap: () => _onFire(TankPlayer.green),
            ),
          ),
          _slot(
            slotHeight,
            TankScoreView(
              player: TankPlayer.red,
              score: _redScore,
              numberOverlay: IgnorePointer(
                child: ScoreSmokeEffect(tick: _redSmokeTick),
              ),
            ),
          ),
          TankJoystick(
            color: TankPlayer.red.color,
            size: slotHeight,
            onDrive: (input) => _onDrive(TankPlayer.red, input),
          ),
        ],
      ),
    );
  }

  /// 右列控制：绿方摇杆 / 绿方比分 / 红方开火钮
  /// 结构与左列完全一致（仅控件种类镜像），保证两列宽度与行位置对称
  Widget _buildRightColumn(double slotHeight) {
    return Padding(
      padding: const EdgeInsets.all(_panelPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TankJoystick(
            color: TankPlayer.green.color,
            size: slotHeight,
            onDrive: (input) => _onDrive(TankPlayer.green, input),
          ),
          _slot(
            slotHeight,
            TankScoreView(
              player: TankPlayer.green,
              score: _greenScore,
              mirrored: true,
              numberOverlay: IgnorePointer(
                child: ScoreSmokeEffect(tick: _greenSmokeTick),
              ),
            ),
          ),
          _slot(
            slotHeight,
            TankFireButton(
              color: TankPlayer.red.color,
              onTap: () => _onFire(TankPlayer.red),
            ),
          ),
        ],
      ),
    );
  }
}
