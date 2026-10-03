import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';
import 'package:horyx/games/aeroplane_chess/services/aeroplane_engine.dart';
import 'package:horyx/games/aeroplane_chess/services/aeroplane_storage.dart';
import 'package:horyx/games/aeroplane_chess/widgets/aeroplane_game_view.dart';
import 'package:horyx/games/aeroplane_chess/widgets/aeroplane_setup_view.dart';
import 'package:horyx/shared/pages/room_page.dart';
import 'package:horyx/shared/profile/profile_controller.dart';
import 'package:horyx/shared/storage/archive_storage.dart';
import 'package:horyx/shared/storage/game_archive_state.dart';
import 'package:horyx/shared/widgets/app_top_bar.dart';
import 'package:horyx/shared/widgets/confirm_dialog.dart';

/// 飞行棋游戏页
/// 持有对局状态与回合流转（掷骰 -> 选子 -> 走子结算），统一负责：
/// 设置视图流转、存档恢复/保存退出、局域网建房入口、终局弹窗与清档
class AeroplanePage extends StatefulWidget {
  const AeroplanePage({super.key, this.resumeArchiveId});

  /// 存档管理页「开始」按钮定点恢复的存档 id；null 表示常规进入
  final String? resumeArchiveId;

  /// 联机房间标识名：GameRegistry 登记、建房入口与房间标识卡共用的
  /// 单一事实来源（注册数据归游戏模块自身，注册中心只做汇总）
  static const String gameName = '飞行棋';

  /// 游戏图标：与 [gameName] 同为注册数据的单一来源
  static const IconData gameIcon = Icons.flight_takeoff_rounded;

  @override
  State<AeroplanePage> createState() => _AeroplanePageState();
}

/// 回合阶段：等待掷骰 / 选子（选子阶段棋子高亮可点、掷骰按钮禁用）
enum _TurnPhase { awaitingRoll, choosing }

class _AeroplanePageState
    extends GameArchiveStateBase<AeroplanePage, AeroplaneGameState> {
  /// 是否已开始对局（false = 对局模式设置阶段）
  bool _started = false;

  /// 当前对局状态（开局初始化或从存档还原）
  AeroplaneGameState? _state;

  /// 回合阶段
  _TurnPhase _phase = _TurnPhase.awaitingRoll;

  /// 最近一次掷骰点数（null = 本局尚未掷骰）
  int? _dice;

  /// 当前骰点下的合法走法缓存（选子阶段）
  List<AeroplaneMove> _moves = const [];

  /// 选中的棋子（颜色, 编号）
  (AeroplaneColor, int)? _selected;

  final Random _random = Random();

  /// 各人数的默认颜色分配：2 人取对角两色（绿+蓝）、
  /// 3 人取连续三方（绿→红→蓝）、4 人全色（枚举顺序即行动顺序）
  static const Map<int, List<AeroplaneColor>> _defaultColors = {
    2: [AeroplaneColor.green, AeroplaneColor.blue],
    3: [AeroplaneColor.green, AeroplaneColor.red, AeroplaneColor.blue],
    4: AeroplaneColor.values,
  };

  @override
  ArchiveStorage<AeroplaneGameState> get archiveStorage =>
      AeroplaneStorage.instance;

  @override
  bool get isInSetupPhase => !_started;

  @override
  void initState() {
    super.initState();
    // 进入页面即检测未完成存档，存在则在设置视图展示恢复入口
    loadSavedState();
    final resumeId = widget.resumeArchiveId;
    if (resumeId != null) {
      resumeArchiveById(resumeId, _applySavedState);
    }
  }

  // ---------------------------------------------------------------------------
  // 回合流转
  // ---------------------------------------------------------------------------

  /// 点击「掷骰子」：随机骰点后结算（三 6 惩罚 / 跳过回合 / 进入选子）
  void _roll() {
    if (_phase != _TurnPhase.awaitingRoll || _state!.gameOver) return;
    final dice = _random.nextInt(6) + 1;
    setState(() => _dice = dice);
    _onDiceRolled(dice);
  }

  void _onDiceRolled(int dice) {
    final state = _state!;
    if (AeroplaneEngine.isThirdSixPenalty(state, dice)) {
      setState(() {
        _state = AeroplaneEngine.applyThirdSixPenalty(state);
        _phase = _TurnPhase.awaitingRoll;
      });
      return;
    }
    final moves = AeroplaneEngine.legalMoves(state, dice);
    if (moves.isEmpty) {
      setState(() {
        _state = AeroplaneEngine.skipTurn(state);
        _phase = _TurnPhase.awaitingRoll;
      });
      return;
    }
    setState(() {
      _moves = moves;
      _phase = _TurnPhase.choosing;
    });
  }

  /// 点击可动棋子：选中（确认行显示「取消/下棋」，有飞越变体时附「飞越」）
  void _onPlaneTap(AeroplaneColor color, int planeId) {
    if (_phase != _TurnPhase.choosing) return;
    if (!_moves.any((m) => m.color == color && m.planeId == planeId)) return;
    setState(() => _selected = (color, planeId));
  }

  List<AeroplaneMove> get _selectedMoves => _selected == null
      ? const []
      : _moves
          .where((m) => m.color == _selected!.$1 && m.planeId == _selected!.$2)
          .toList();

  /// 确认走子：执行迁移并瞬时落位（被撞棋子随新状态归位）。
  /// 选中棋子恰好落在己方加油站起点格（存在飞越变体）时一律飞越，
  /// 不提供不飞越的走法选择
  void _confirmMove() => _executeMove(
        _selectedMoves.firstWhere((m) => m.fly,
            orElse: () => _selectedMoves.first),
      );

  void _executeMove(AeroplaneMove move) {
    final newState = AeroplaneEngine.applyMove(_state!, move, _dice!);
    setState(() {
      _state = newState;
      _phase = _TurnPhase.awaitingRoll;
      _moves = const [];
      _selected = null;
    });
    if (newState.gameOver) {
      _onGameOver();
    }
  }

  /// 终局：清档（避免重进恢复出已终局对局）+ 结果弹窗
  Future<void> _onGameOver() async {
    unawaited(
      clearCurrentArchive().onError((e, stackTrace) {
        debugPrint('终局清档失败: $e');
      }),
    );
    final winner = _state!.winner!;
    final result = await showConfirmDialog(
      context,
      title: '${winner.label}方胜利！',
      message: '4 架飞机全部抵达终点',
      confirmLabel: '再来一局',
      neutralLabel: '返回设置',
    );
    if (!mounted) return;
    switch (result) {
      case ConfirmResult.confirm:
        _restartMatch();
      case ConfirmResult.neutral:
        _backToSetup();
      case ConfirmResult.cancel:
        // 留在终局棋盘查看局面
        break;
    }
  }

  /// 再来一局：同配置重开新对局
  void _restartMatch() {
    setState(() {
      _state = _initialState(_state!.players);
      _resetRound();
    });
  }

  // ---------------------------------------------------------------------------
  // 设置/恢复/退出
  // ---------------------------------------------------------------------------

  /// 可动棋子集合（仅选子阶段高亮可点）
  Set<(AeroplaneColor, int)> get _movable => _phase == _TurnPhase.choosing
      ? {for (final m in _moves) (m.color, m.planeId)}
      : {};

  /// 恢复未完成对局：从存档还原对局状态
  void _resumeSaved() {
    final saved = takeResumeEntry();
    if (saved == null) return;
    _applySavedState(saved);
  }

  /// 将存档状态还原进对局视图（恢复入口与存档管理页「开始」共用）。
  /// 存档模型构造时已校验不变式、读取侧已容错损坏数据，
  /// 无需页面级二次校验。骰点不入档，恢复后回到等待掷骰
  void _applySavedState(AeroplaneGameState saved) {
    setState(() {
      _state = saved;
      _started = true;
      _resetRound();
    });
  }

  /// 开始本地对局：进入对局视图，初始化开局状态（全部棋子在停机坪，
  /// 座位顺序首位先手），并解绑恢复入口（此后保存新建存档）
  void _onStart(int playerCount) {
    final players = [
      for (var i = 0; i < playerCount; i++)
        AeroplanePlayer(
          color: _defaultColors[playerCount]![i],
          name: '玩家${i + 1}',
        ),
    ];
    setState(() {
      _state = _initialState(players);
      _started = true;
      _resetRound();
      discardResumeEntry();
    });
  }

  AeroplaneGameState _initialState(List<AeroplanePlayer> players) =>
      AeroplaneGameState(
        players: players,
        planes: {
          for (final player in players)
            player.color: [
              for (var i = 0; i < 4; i++)
                PlanePosition(zone: PlaneZone.hangar, index: i),
            ],
        },
        currentPlayer: players.first.color,
        consecutiveSixes: 0,
        gameOver: false,
        winner: null,
        savedAt: DateTime.now(),
      );

  /// 清空回合内临时状态，回到等待掷骰
  void _resetRound() {
    _phase = _TurnPhase.awaitingRoll;
    _dice = null;
    _moves = const [];
    _selected = null;
  }

  /// 局域网模式：创建房间并进入等待页（容量 2..4，自己为玩家 1）。
  /// 联机对局页自后续阶段接入，hostGameBuilder 留空——
  /// 满员后等待页停留「即将开始」（联机未接入的既有兜底，不报错）
  Future<void> _createRoom(int capacity) async {
    if (!await ensureProfileForOnline(context)) return;
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomPage.host(
          gameName: AeroplanePage.gameName,
          hostName: ProfileScope.of(context).name,
          icon: AeroplanePage.gameIcon,
          capacity: capacity,
        ),
      ),
    );
  }

  /// 返回设置视图并刷新存档检测（终局弹窗「返回设置」路径）
  void _backToSetup() {
    _resetForSetup();
    loadSavedState();
  }

  /// 清空对局状态回到设置视图（不含存档检测——退出模板的回设置分支
  /// 与 [_backToSetup] 各自统一负责刷新，避免双份加载）
  void _resetForSetup() {
    setState(() {
      _state = null;
      _started = false;
      _resetRound();
    });
  }

  /// 退出请求：设置阶段直接退出页面；对局阶段尚无走子存档语义
  /// （三选项保存确认自下一阶段接入），一律回设置视图不打扰
  Future<void> _requestExit() async {
    await requestExitWithArchive(
      this,
      hasProgress: _started,
      hasMoves: false,
      unchangedSinceRestore: false,
      onSave: () async {
        final state = _state;
        if (state == null) return;
        await saveCurrent(
          _copyWithSavedAt(state, DateTime.now()),
        );
      },
      onBackToSetup: _resetForSetup,
      exitPage: () => Navigator.of(context).pop(),
    );
  }

  /// 组装存档：刷新存档时间，其余沿用当前对局状态
  AeroplaneGameState _copyWithSavedAt(AeroplaneGameState state, DateTime now) =>
      AeroplaneGameState(
        players: state.players,
        planes: state.planes,
        currentPlayer: state.currentPlayer,
        consecutiveSixes: state.consecutiveSixes,
        lastMoved: state.lastMoved,
        gameOver: state.gameOver,
        winner: state.winner,
        savedAt: now,
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 对局阶段拦截系统返回（回设置视图），设置阶段允许直接返回
      canPop: !_started,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestExit();
      },
      child: Scaffold(
        body: SafeArea(
          // 顶部由 AppTopBar 自行吸收状态栏（表面色整体延伸），此处不再避让
          top: false,
          bottom: false,
          child: Column(
            children: [
              AppTopBar(
                title: AeroplanePage.gameName,
                showBack: true,
                onBack: _requestExit,
              ),
              Expanded(
                // 阶段切换动画：设置视图 <-> 对局视图
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _started ? _buildGameView() : _buildSetupView(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSetupView() => AeroplaneSetupView(
        key: const ValueKey('setup'),
        onStart: _onStart,
        onCreateRoom: _createRoom,
        savedState: savedState,
        onResume: _resumeSaved,
      );

  /// 对局视图组装
  Widget _buildGameView() {
    final state = _state;
    if (state == null) {
      // 不变式：_started 为 true 时必有对局状态，此分支不可达（纯防御）。
      // 不可在 build 期间调 _resetForSetup()（内含 setState 会抛框架错误），
      // 改为 debug 断言暴露回归、release 渲染占位帧；顶栏返回仍可退出
      assert(false, '_started 为 true 时 _state 不应为 null');
      return const SizedBox.shrink();
    }
    return AeroplaneGameView(
      key: const ValueKey('board'),
      state: state,
      dice: _dice,
      canRoll: _phase == _TurnPhase.awaitingRoll && !state.gameOver,
      movable: _movable,
      selected: _selected,
      onRoll: _roll,
      onPlaneTap: _onPlaneTap,
      onCancelMove: () => setState(() => _selected = null),
      onConfirmMove: _confirmMove,
      onRestart: _restartMatch,
    );
  }
}
