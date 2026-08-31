import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:horyx/games/tank/game/tank_maze_game.dart';
import 'package:horyx/games/tank/models/tank_maze.dart';
import 'package:horyx/games/tank/models/tank_player.dart';
import 'package:horyx/games/tank/services/tank_online_controller.dart';
import 'package:horyx/games/tank/widgets/score_smoke_effect.dart';
import 'package:horyx/games/tank/widgets/tank_fire_button.dart';
import 'package:horyx/games/tank/widgets/tank_joystick.dart';
import 'package:horyx/games/tank/widgets/tank_score_view.dart';
import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/network/room_host.dart';
import 'package:horyx/shared/widgets/online_game_page_shell.dart';

/// 坦克动荡联机对局页（横屏沉浸，无顶栏）
/// 由房间等待页满员开局后接管房间连接（房主/客户端所有权移入本页）。
/// 角色映射与五子棋惯例一致：房主（座位 1）= 红方，客户端（座位 2）= 绿方；
/// 双方看同一方向战场（客户端不做画面翻转）。
/// 布局与本地对局页一致（两列三槽、比分原位）；联机双方各自正持设备，
/// 己方控件统一落位本地红方的操作位（左列底部摇杆 + 右列底部开火钮），
/// 仅以颜色区分角色（房主红 / 客户端绿），本地绿方控件的原位槽留空保位。
/// 房主的驾驶/开火直接下发本地战场，客户端经控制器上报网络、
/// 影子战场按快照渲染。联机对局不写本地存档，页面销毁即退出对局
/// 并关闭连接。
class TankOnlinePage extends StatefulWidget {
  const TankOnlinePage.host({super.key, required this.host}) : client = null;

  const TankOnlinePage.client({super.key, required this.client})
      : host = null;

  /// 房主连接（房主模式）
  final RoomHost? host;

  /// 客户端连接（客户端模式）
  final RoomClient? client;

  @override
  State<TankOnlinePage> createState() => _TankOnlinePageState();
}

class _TankOnlinePageState extends State<TankOnlinePage> {
  /// 我方角色：房主 = 红方（座位 1），客户端 = 绿方（座位 2）
  TankPlayer get _myPlayer =>
      widget.host != null ? TankPlayer.red : TankPlayer.green;

  /// 战场：房主 = 本地模拟；客户端 = 远程快照驱动的影子战场。
  /// 客户端构造时用本地占位迷宫（收到房主回合消息后按种子重建），
  /// 首屏短暂为占位内容，由随后的快照驱动为真实战场
  late final TankMazeGame _game = TankMazeGame(
    maze: TankMaze.generate(),
    remote: widget.host == null,
  );

  /// 联机控制器引用（shell 创建时存下，输入转发用；生命周期由
  /// shell 统一管理——dispose 即关闭房间连接——页面不得重复 dispose）
  TankOnlineController? _controller;

  /// 双方得分烟雾触发计数（比分上升瞬间自增，驱动数字上的烟雾特效）
  int _redSmokeTick = 0;
  int _greenSmokeTick = 0;

  /// 上次构建时读到的比分（得分瞬间 diff 用）
  int _lastRedScore = 0;
  int _lastGreenScore = 0;

  @override
  void initState() {
    super.initState();
    // 横屏 + 沉浸式（同本地对局页），退出页面时在 dispose 还原
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// 还原竖屏与系统 UI：退出确认/终局弹窗后先还原再 pop（旋转与
  /// 转场动画并行，退出无延迟——同本地对局页的退出处理）；
  /// dispose 中同样调用作兜底（覆盖未经确认弹窗的 pop 路径）
  void _restoreOrientation() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    _restoreOrientation();
    super.dispose();
  }

  /// 控制器工厂（shell initState 调用一次）：创建后立即挂接战场——
  /// 战场在页面 initState 已就绪；客户端此刻应用挂接前暂存的
  /// 回合/快照，战场挂接即显示正确内容
  TankOnlineController _createController() {
    final controller = widget.host != null
        ? TankOnlineController.host(widget.host!)
        : TankOnlineController.client(widget.client!);
    if (widget.host != null) {
      controller.attachHostGame(_game);
    } else {
      controller.attachClientGame(_game);
    }
    _controller = controller;
    return controller;
  }

  /// 比分变化 diff（由控制器通知驱动的构建时机调用）：
  /// 比分上升瞬间自增烟雾计数；比分本体以战场为准，页面只读
  void _diffScores() {
    if (_game.redScore != _lastRedScore) {
      if (_game.redScore > _lastRedScore) _redSmokeTick++;
      _lastRedScore = _game.redScore;
    }
    if (_game.greenScore != _lastGreenScore) {
      if (_game.greenScore > _lastGreenScore) _greenSmokeTick++;
      _lastGreenScore = _game.greenScore;
    }
  }

  /// 驾驶输入：房主直接下发本地战场（自己 = 红方）；
  /// 客户端上报网络（房主执行后经快照回传驱动影子战场）
  void _onDrive(TankDriveInput? input) {
    final controller = _controller;
    if (controller == null) return;
    if (widget.host != null) {
      _game.setDrive(TankPlayer.red, input);
    } else {
      controller.sendDrive(input);
    }
  }

  /// 开火：房主经控制器执行本地发射并广播开火事件（客户端同步音效）；
  /// 客户端上报开火请求（是否实际发射由房主裁决，音效随事件回传）
  void _onFire() {
    final controller = _controller;
    if (controller == null) return;
    if (widget.host != null) {
      controller.hostFire();
    } else {
      controller.sendFire();
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnlineGamePageShell<TankOnlineController>(
      title: '坦克动荡 · 联机',
      exitMessage: '退出后将断开与房间的连接，对局将结束',
      createController: _createController,
      // 与本地对局页一致：横屏沉浸无顶栏（退出经系统返回触发确认流程）；
      // 退出确认/终局弹窗后先还原竖屏再 pop（无延迟退出）
      showTopBar: false,
      onBeforeExit: _restoreOrientation,
      buildGameView: (context, controller, requestExit) {
        // 控制器通知（含比分变化）驱动的重建时机：先 diff 得分瞬间
        // 再构建视图，保证比分数字与烟雾特效同步出现
        _diffScores();
        return _BattleView(
          game: _game,
          myPlayer: _myPlayer,
          redSmokeTick: _redSmokeTick,
          greenSmokeTick: _greenSmokeTick,
          onDrive: _onDrive,
          onFire: _onFire,
        );
      },
    );
  }
}

/// 联机战场视图：布局复刻本地对局页（两列控制、三行等高槽位、比分原位）；
/// 联机双方各自正持设备看同一方向战场，己方控件统一落位本地红方的
/// 操作位（左列底部摇杆 + 右列底部开火钮），仅以颜色区分角色
/// （房主红 / 客户端绿），本地绿方控件的原位槽留空保位：
/// - 左列（自上而下）：空槽（本地绿方开火钮位）/ 红方比分 / 己方摇杆
/// - 右列（自上而下）：空槽（本地绿方摇杆位）/ 绿方比分 / 己方开火钮
class _BattleView extends StatelessWidget {
  const _BattleView({
    required this.game,
    required this.myPlayer,
    required this.redSmokeTick,
    required this.greenSmokeTick,
    required this.onDrive,
    required this.onFire,
  });

  /// 联机战场（比分读取源；坦克/子弹由 Flame 内部渲染）
  final TankMazeGame game;

  /// 我方角色（决定我方控件落位，对方控件槽位留空）
  final TankPlayer myPlayer;

  /// 双方得分烟雾触发计数
  final int redSmokeTick;
  final int greenSmokeTick;

  /// 驾驶/开火回调（页面上报路由见 [_TankOnlinePageState]）
  final ValueChanged<TankDriveInput?> onDrive;
  final VoidCallback onFire;

  /// 摇杆列四周留白：圆钮推出底座时会越过摇杆区域约半个钮径
  /// （最大约槽高 12%+，140 槽时约 34px），留白必须覆盖之——
  /// 否则圆钮会被后绘制的地图区盖住、伸出屏幕外（同本地对局页）
  static const double _panelPadding = 40;

  /// 等高槽位：较小控件（开火钮/比分）在槽内居中
  Widget _slot(double height, Widget? child) => SizedBox(
        height: height,
        child: Center(child: child),
      );

  Widget _emptySlot(double height) => SizedBox(height: height, width: height);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 挖孔/刘海在横屏下只产生单侧 inset，取较大值避让，
        // 保证左右操作区到屏幕边缘的距离完全对称（同本地对局页）
        final insets = MediaQuery.of(context).padding;
        final hCutout = math.max(insets.left, insets.right);
        // 三行等高槽位随屏幕高度收缩（下限 104 防控件过小），
        // 80 = 摇杆列上下留白 ×2（同本地对局页）
        final slotHeight = math.max(
            104.0, math.min(140.0, (constraints.maxHeight - 80) / 3));
        return Padding(
          padding: EdgeInsets.fromLTRB(hCutout, 0, hCutout, 0),
          child: Row(
            children: [
              _buildLeftColumn(slotHeight),
              // 战场区域：Flame 画布渲染本局迷宫（房主模拟/影子战场）
              Expanded(child: GameWidget(game: game)),
              _buildRightColumn(slotHeight),
            ],
          ),
        );
      },
    );
  }

  /// 左列控制：空槽（本地绿方开火钮位）/ 红方比分 / 己方摇杆（底部）
  Widget _buildLeftColumn(double slotHeight) {
    return Padding(
      padding: const EdgeInsets.all(_panelPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _emptySlot(slotHeight),
          _slot(
            slotHeight,
            TankScoreView(
              player: TankPlayer.red,
              score: game.redScore,
              numberOverlay: IgnorePointer(
                child: ScoreSmokeEffect(tick: redSmokeTick),
              ),
            ),
          ),
          TankJoystick(
            color: myPlayer.color,
            size: slotHeight,
            onDrive: onDrive,
          ),
        ],
      ),
    );
  }

  /// 右列控制：空槽（本地绿方摇杆位）/ 绿方比分 / 己方开火钮（底部）
  Widget _buildRightColumn(double slotHeight) {
    return Padding(
      padding: const EdgeInsets.all(_panelPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _emptySlot(slotHeight),
          _slot(
            slotHeight,
            TankScoreView(
              player: TankPlayer.green,
              score: game.greenScore,
              mirrored: true,
              numberOverlay: IgnorePointer(
                child: ScoreSmokeEffect(tick: greenSmokeTick),
              ),
            ),
          ),
          _slot(
            slotHeight,
            TankFireButton(
              color: myPlayer.color,
              onTap: onFire,
            ),
          ),
        ],
      ),
    );
  }
}
