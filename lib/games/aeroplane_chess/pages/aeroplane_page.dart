import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_board.dart';
import 'package:horyx/games/aeroplane_chess/models/aeroplane_colors.dart';
import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';
import 'package:horyx/games/aeroplane_chess/services/aeroplane_engine.dart';
import 'package:horyx/games/aeroplane_chess/services/aeroplane_storage.dart';
import 'package:horyx/games/aeroplane_chess/widgets/aeroplane_game_view.dart';
import 'package:horyx/games/aeroplane_chess/widgets/aeroplane_setup_view.dart';
import 'package:horyx/shared/pages/room_page.dart';
import 'package:horyx/shared/profile/profile_controller.dart';
import 'package:horyx/shared/storage/archive_storage.dart';
import 'package:horyx/shared/storage/game_archive_state.dart';
import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/widgets/app_top_bar.dart';
import 'package:horyx/shared/widgets/confirm_dialog.dart';

/// 飞行棋游戏页
/// 持有对局状态与回合流转（掷骰翻动 -> 选子 -> 走子逐格动画 -> 结算
/// 提示），统一负责：设置视图流转、存档恢复/保存退出、局域网建房入口、
/// 终局弹窗与清档
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

/// 回合阶段：等待掷骰 / 骰子滚动 / 选子 / 走子动画（动画期间锁输入）
enum _TurnPhase { awaitingRoll, rolling, choosing, moving }

class _AeroplanePageState
    extends GameArchiveStateBase<AeroplanePage, AeroplaneGameState> {
  /// 是否已开始对局（false = 对局模式设置阶段）
  bool _started = false;

  /// 当前对局状态（开局初始化或从存档还原）
  AeroplaneGameState? _state;

  /// 回合阶段
  _TurnPhase _phase = _TurnPhase.awaitingRoll;

  /// 展示中的骰点（滚动中为翻动值；null = 本局尚未掷骰）
  int? _dice;

  /// 当前骰点下的合法走法缓存（选子阶段）
  List<AeroplaneMove> _moves = const [];

  /// 选中的棋子（颜色, 编号）
  (AeroplaneColor, int)? _selected;

  /// 走子动画：路径点（格子坐标）与推进序号、移动中的棋子
  List<Point<double>>? _movePath;
  int _moveStep = 0;
  (AeroplaneColor, int)? _movingPlane;

  /// 覆盖层提示（触发序号递增播放，文本为空不显示）
  int _hintTrigger = 0;
  String _hintText = '';
  Color _hintColor = AeroplaneColors.red;

  final Random _random = Random();

  Timer? _rollTimer;
  Timer? _moveTimer;

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

  @override
  void dispose() {
    _rollTimer?.cancel();
    _moveTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 回合流转
  // ---------------------------------------------------------------------------

  /// 点击「掷骰子」：骰面快速翻动后定格结果，随后进入三 6 惩罚 /
  /// 跳过回合 / 选子分支
  void _roll() {
    if (_phase != _TurnPhase.awaitingRoll || _state!.gameOver) return;
    setState(() {
      _phase = _TurnPhase.rolling;
      _selected = null;
      _moves = const [];
    });
    var ticks = 0;
    _rollTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      ticks++;
      if (ticks < 10) {
        setState(() => _dice = _random.nextInt(6) + 1);
        return;
      }
      timer.cancel();
      final result = _random.nextInt(6) + 1;
      setState(() => _dice = result);
      _onDiceRolled(result);
    });
  }

  /// 骰点结算：三 6 惩罚（动画滑回停机坪）/ 无可动跳过 / 进入选子
  void _onDiceRolled(int dice) {
    final state = _state!;
    if (AeroplaneEngine.isThirdSixPenalty(state, dice)) {
      final target = state.lastMoved;
      final newState = AeroplaneEngine.applyThirdSixPenalty(state);
      // 与引擎同口径：已抵达终点者不受罚（无可罚时直接换人）
      if (target != null &&
          target.$1 == state.currentPlayer &&
          state.planesOf(target.$1)[target.$2].zone != PlaneZone.goal) {
        _animateMove(
          to: newState,
          plane: target,
          path: [
            _planeCoord(state, target.$1, target.$2),
            _planeCoord(newState, target.$1, target.$2),
          ],
          onDone: () => _hint('连续三个 6！最后移动的飞机返回停机坪', AeroplaneColors.yellow),
        );
      } else {
        setState(() {
          _state = newState;
          _phase = _TurnPhase.awaitingRoll;
        });
        _hint(
          '连续三个 6！${newState.currentPlayer.label}方行动',
          AeroplaneColors.yellow,
        );
      }
      return;
    }
    final moves = AeroplaneEngine.legalMoves(state, dice);
    if (moves.isEmpty) {
      final newState = AeroplaneEngine.skipTurn(state);
      setState(() {
        _state = newState;
        _phase = _TurnPhase.awaitingRoll;
      });
      _hint('无可动棋子，跳过回合', context.palette.textSecondary);
      return;
    }
    setState(() {
      _moves = moves;
      _phase = _TurnPhase.choosing;
    });
  }

  /// 点击可动棋子：选中（确认行显示「取消/下棋」）
  void _onPlaneTap(AeroplaneColor color, int planeId) {
    if (_phase != _TurnPhase.choosing) return;
    if (!_moves.any((m) => m.color == color && m.planeId == planeId)) return;
    setState(() => _selected = (color, planeId));
  }

  List<AeroplaneMove> get _selectedMoves => _selected == null
      ? const []
      : _moves
            .where(
              (m) => m.color == _selected!.$1 && m.planeId == _selected!.$2,
            )
            .toList();

  /// 确认走子：执行迁移并逐格动画落位（被撞棋子随新状态归位）。
  /// 选中棋子恰好落在己方加油站起点格（存在飞越变体）时一律飞越，
  /// 不提供不飞越的走法选择
  void _confirmMove() => _executeMove(
    _selectedMoves.firstWhere((m) => m.fly, orElse: () => _selectedMoves.first),
  );

  void _executeMove(AeroplaneMove move) {
    final state = _state!;
    final newState = AeroplaneEngine.applyMove(state, move, _dice!);
    _animateMove(
      to: newState,
      plane: (move.color, move.planeId),
      path: _buildMovePath(state, move, _dice!, newState),
      onDone: () => _onMoveDone(newState, move.color),
    );
  }

  /// 走子结算：终局弹窗 / 再掷提示（撞子、飞越、跳跃、掷 6 统一文案）
  void _onMoveDone(AeroplaneGameState newState, AeroplaneColor mover) {
    if (newState.gameOver) {
      _onGameOver();
      return;
    }
    if (newState.currentPlayer != mover) {
      return;
    }
    _hint('奖励再掷一次', context.palette.primary);
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

  /// 走子/惩罚动画：按路径点逐段推进（每段 140ms），动画期间锁输入，
  /// 结束时应用目标状态并回调结算
  void _animateMove({
    required AeroplaneGameState to,
    required (AeroplaneColor, int) plane,
    required List<Point<double>> path,
    required VoidCallback onDone,
  }) {
    setState(() {
      _phase = _TurnPhase.moving;
      _selected = null;
      _moves = const [];
      _movingPlane = plane;
      _movePath = path;
      _moveStep = 0;
    });
    _moveTimer = Timer.periodic(const Duration(milliseconds: 140), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_moveStep < path.length - 1) {
        setState(() => _moveStep++);
        return;
      }
      timer.cancel();
      setState(() {
        _state = to;
        _phase = _TurnPhase.awaitingRoll;
        _movingPlane = null;
        _movePath = null;
        _moveStep = 0;
      });
      onDone();
    });
  }

  /// 触发覆盖层提示
  void _hint(String text, Color color) {
    setState(() {
      _hintTrigger++;
      _hintText = text;
      _hintColor = color;
    });
  }

  // ---------------------------------------------------------------------------
  // 走子路径推导
  // ---------------------------------------------------------------------------

  /// 走法迁移的动画路径（格子坐标停留点序列）：
  /// 普通行进逐格推进；超出终点冲至尽头再逐格回退；跳跃/回退后跳跃
  /// 一次滑到最终落点；飞越先逐格至航线起点、直线插值飞至落点，
  /// 落点再接跳跃同样一次滑到最终点
  List<Point<double>> _buildMovePath(
    AeroplaneGameState state,
    AeroplaneMove move,
    int dice,
    AeroplaneGameState newState,
  ) {
    final color = move.color;
    final old = state.planesOf(color)[move.planeId];
    final newPos = newState.planesOf(color)[move.planeId];
    final points = <Point<double>>[_planeCoord(state, color, move.planeId)];
    if (old.zone == PlaneZone.hangar) {
      // 起飞直达起飞格（起飞落点不触发连锁）
      points.add(_planeCoord(newState, color, move.planeId));
      return points;
    }
    final total = AeroplaneEngine.totalSteps(color);
    final finalSteps = newPos.zone == PlaneZone.goal
        ? total
        : AeroplaneEngine.journeySteps(color, newPos);
    // 准备区出发：起飞格为第 1 步，行进段自 journey 1 起
    final s0 = old.zone == PlaneZone.ready
        ? 0
        : AeroplaneEngine.journeySteps(color, old);
    // 准备区掷 N 落 journey N-1（比常规少 1 步：起飞格占第 1 步）
    final effectiveDice = old.zone == PlaneZone.ready ? dice - 1 : dice;

    if (move.fly) {
      final route = AeroplaneBoard.flightRoutes[color]!;
      final startSteps =
          (route.start - AeroplaneBoard.takeoffIndex[color]!) %
          AeroplaneBoard.ringSize;
      for (var s = s0 + 1; s <= startSteps; s++) {
        points.add(_stepsCoord(color, s));
      }
      // 飞越段直线插值（快速滑过虚线航线）
      final landing = AeroplaneBoard.ringAnchor(route.landing);
      final last = points.last;
      for (var i = 1; i <= 3; i++) {
        final t = i / 4;
        points.add(
          Point(
            last.x + (landing.x - last.x) * t,
            last.y + (landing.y - last.y) * t,
          ),
        );
      }
      final landingSteps =
          (route.landing - AeroplaneBoard.takeoffIndex[color]!) %
          AeroplaneBoard.ringSize;
      points.add(
        finalSteps == landingSteps
            ? landing
            : _planeCoord(newState, color, move.planeId),
      );
      return points;
    }

    final raw = s0 + effectiveDice;
    final forwardEnd = min(raw, total);
    for (var s = s0 + 1; s <= forwardEnd; s++) {
      points.add(_stepsCoord(color, s));
    }
    if (raw > total) {
      final landSteps = 2 * total - raw;
      for (var s = total - 1; s >= landSteps; s--) {
        points.add(_stepsCoord(color, s));
      }
      if (finalSteps != landSteps) {
        points.add(_planeCoord(newState, color, move.planeId));
      }
    } else if (finalSteps != raw) {
      points.add(_planeCoord(newState, color, move.planeId));
    }
    return points;
  }

  /// 累计步数 → 格子坐标（行进途中经停点）
  Point<double> _stepsCoord(AeroplaneColor color, int steps) {
    final pos = AeroplaneEngine.positionAtSteps(color, steps);
    return switch (pos.zone) {
      PlaneZone.ring => AeroplaneBoard.ringAnchor(pos.index),
      PlaneZone.runway => AeroplaneBoard.runwayCellCenter(color, pos.index),
      _ => AeroplaneBoard.goalCellCenter(color),
    };
  }

  /// 对局状态中的棋子 → 格子坐标
  Point<double> _planeCoord(
    AeroplaneGameState state,
    AeroplaneColor color,
    int planeId,
  ) {
    final pos = state.planesOf(color)[planeId];
    return switch (pos.zone) {
      PlaneZone.hangar => AeroplaneBoard.hangarSlotCenter(color, pos.index),
      PlaneZone.ready => AeroplaneBoard.readyCellCenter(color),
      PlaneZone.ring => AeroplaneBoard.ringAnchor(pos.index),
      PlaneZone.runway => AeroplaneBoard.runwayCellCenter(color, pos.index),
      PlaneZone.goal => AeroplaneBoard.goalCellCenter(color),
    };
  }

  // ---------------------------------------------------------------------------
  // 视图状态（供对局视图消费）
  // ---------------------------------------------------------------------------

  Set<(AeroplaneColor, int)> get _movable => _phase == _TurnPhase.choosing
      ? {for (final m in _moves) (m.color, m.planeId)}
      : {};

  (AeroplaneColor, int, Point<double>)? get _movingOverride {
    if (_phase != _TurnPhase.moving ||
        _movingPlane == null ||
        _movePath == null) {
      return null;
    }
    return (_movingPlane!.$1, _movingPlane!.$2, _movePath![_moveStep]);
  }

  // ---------------------------------------------------------------------------
  // 设置/恢复/退出
  // ---------------------------------------------------------------------------

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

  /// 清空回合内临时状态（掷骰/选子/动画），回到等待掷骰
  void _resetRound() {
    _rollTimer?.cancel();
    _moveTimer?.cancel();
    _phase = _TurnPhase.awaitingRoll;
    _dice = null;
    _moves = const [];
    _selected = null;
    _movingPlane = null;
    _movePath = null;
    _moveStep = 0;
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
        await saveCurrent(_copyWithSavedAt(state, DateTime.now()));
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
      rolling: _phase == _TurnPhase.rolling,
      canRoll: _phase == _TurnPhase.awaitingRoll && !state.gameOver,
      movable: _movable,
      selected: _selected,
      movingOverride: _movingOverride,
      onRoll: _roll,
      onPlaneTap: _onPlaneTap,
      onCancelMove: () => setState(() => _selected = null),
      onConfirmMove: _confirmMove,
      onRestart: _restartMatch,
      hintTrigger: _hintTrigger,
      hintText: _hintText,
      hintColor: _hintColor,
    );
  }
}
