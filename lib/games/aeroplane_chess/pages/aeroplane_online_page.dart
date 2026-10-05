import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_colors.dart';
import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';
import 'package:horyx/games/aeroplane_chess/services/aeroplane_engine.dart';
import 'package:horyx/games/aeroplane_chess/services/aeroplane_online_controller.dart';
import 'package:horyx/games/aeroplane_chess/widgets/aeroplane_board_view.dart';
import 'package:horyx/games/aeroplane_chess/widgets/aeroplane_dice.dart';
import 'package:horyx/games/aeroplane_chess/widgets/aeroplane_move_animation.dart';
import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/network/room_host.dart';
import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/utils/hint_bar.dart';
import 'package:horyx/shared/widgets/board_game_online_page.dart';
import 'package:horyx/shared/widgets/confirm_move_row.dart';
import 'package:horyx/shared/widgets/flash_hint.dart';
import 'package:horyx/shared/widgets/online_game_page_shell.dart';
import 'package:horyx/shared/widgets/page_content.dart';
import 'package:horyx/shared/widgets/primary_button.dart';
import 'package:horyx/shared/widgets/turn_card.dart';

/// 飞行棋联机对局页
/// 由房间等待页满员开局后接管房间连接（房主/客户端所有权移入本页）。
/// 页面骨架（控制器生命周期/终局弹窗/退出确认/顶栏框架）见
/// [OnlineGamePageShell]，本页不接入认输与悔棋（与本地一致），
/// 中途退出/断线按断线终局处理（由基类与骨架承载）。
/// 视图与本地对局同构（回合卡 + 棋盘 + 骰面 + 走子确认 + 操作按钮），
/// 共用棋盘/棋子/回合组件与走子动画器；联机适配点：骰点与状态均来自
/// 房主广播（客户端不生成骰点），走子经房主裁决后随快照全端生效，
/// 客户端由迁移前后状态经同源引擎重放推断走法，还原与本地一致的
/// 逐格/飞越/撞子动画。页面销毁即退出对局并关闭连接（不落本地存档）。
class AeroplaneOnlinePage extends StatefulWidget {
  const AeroplaneOnlinePage.host({super.key, required this.host})
    : client = null;

  const AeroplaneOnlinePage.client({super.key, required this.client})
    : host = null;

  /// 房主连接（房主模式；与本页生命周期绑定，dispose 时关闭即解散房间）
  final RoomHost? host;

  /// 客户端连接（客户端模式；dispose 时关闭即退出房间）
  final RoomClient? client;

  @override
  State<AeroplaneOnlinePage> createState() => _AeroplaneOnlinePageState();
}

class _AeroplaneOnlinePageState extends State<AeroplaneOnlinePage>
    with SingleTickerProviderStateMixin {
  /// 联机控制器（shell 创建时存下；生命周期由 shell 统一管理，
  /// 页面不得重复 dispose）
  AeroplaneOnlineController? _controller;

  /// 棋盘展示的对局状态：动画期间保持迁移前状态（移动棋子由动画器
  /// 帧坐标覆盖呈现），动画结束切换为迁移后快照；其余时刻随控制器同步
  AeroplaneGameState? _display;

  /// 动画目标快照（动画期间新快照到达的防御落地基准）
  AeroplaneGameState? _pendingTo;

  /// 选中的棋子（颜色, 编号）
  (AeroplaneColor, int)? _selected;

  /// 已提交走子待快照同步（客户端往返期间锁输入防重复提交）
  bool _lockInput = false;

  /// 展示中的骰点（翻动中为随机值；null = 本局尚未掷骰）
  int? _dice;

  /// 上一通知的 pendingDice 快照（null = 未在掷骰等待）：以「空转非空」
  /// 识别新骰点广播驱动翻动，骰点值相同的新一掷同样触发
  int? _lastSeenDice;

  bool _rolling = false;

  Timer? _rollTimer;

  final Random _random = Random();

  late final AeroplaneMoveAnimator _animator = AeroplaneMoveAnimator(
    vsync: this,
  );

  /// 覆盖层提示（触发序号递增播放，文本为空不显示）
  int _hintTrigger = 0;
  String _hintText = '';
  Color _hintColor = AeroplaneColors.red;

  /// 胜负弹窗只弹一次（无胜负终止弹窗由骨架处理，各用各的标志）
  bool _winDialogShown = false;

  /// 终局动画进行中收到的胜负终局：动画播完再弹（避免弹窗遮住
  /// 完成飞回的动画过程）
  bool _pendingWinDialog = false;

  @override
  void dispose() {
    _rollTimer?.cancel();
    _animator.dispose();
    super.dispose();
  }

  AeroplaneOnlineController _createController() {
    final controller = widget.host != null
        ? AeroplaneOnlineController.host(widget.host!)
        : AeroplaneOnlineController.client(widget.client!);
    _controller = controller;
    return controller;
  }

  // ---------------------------------------------------------------------------
  // 控制器状态同步（经骨架 onControllerChanged 在 build 路径外调用）
  // ---------------------------------------------------------------------------

  void _onControllerChanged(AeroplaneOnlineController controller) {
    // 新骰点广播（pendingDice 由空转非空，迁移消费后复位）驱动骰面
    // 翻动：自己掷与对方掷共用同一动效，骰点值相同的新一掷也触发
    final dice = controller.pendingDice;
    if (dice != null && _lastSeenDice == null) {
      _lastSeenDice = dice;
      _startRollAnimation(dice);
    } else if (dice == null) {
      _lastSeenDice = null;
    }
    final next = controller.state;
    final prev = _display;
    if (next == null || identical(prev, next)) return;
    if (prev == null) {
      _display = next;
      return;
    }
    if (_animator.animating) {
      // 回合制下动画期间不应有新迁移；防御：丢弃未完成动画直接落地，
      // 避免展示状态与权威快照脱节
      _animator.reset();
      final base = _pendingTo ?? prev;
      _pendingTo = null;
      _applyTransition(base, next);
      return;
    }
    _applyTransition(prev, next);
  }

  /// 应用一次迁移：diff 前后状态还原动画（惩罚飞回 / 重放推断的
  /// 走子逐格 + 被撞飞回），无棋子迁移（换人跳过）直接落地
  void _applyTransition(AeroplaneGameState prev, AeroplaneGameState next) {
    final mover = prev.currentPlayer;
    (AeroplaneColor, int)? movedPlane;
    var penalty = false;
    final capturedFlights =
        <((AeroplaneColor, int), Point<double>, Point<double>)>[];
    for (final entry in prev.planes.entries) {
      final color = entry.key;
      final after = next.planesOf(color);
      for (var i = 0; i < entry.value.length; i++) {
        final before = entry.value[i];
        if (before == after[i]) continue;
        if (color == mover) {
          movedPlane ??= (color, i);
          // 行动方棋子回停机坪只发生在三 6 惩罚
          if (after[i].zone == PlaneZone.hangar) penalty = true;
        } else if (after[i].zone == PlaneZone.hangar) {
          capturedFlights.add((
            (color, i),
            planeCoord(prev, color, i),
            planeCoord(next, color, i),
          ));
        }
      }
    }
    if (movedPlane == null) {
      _display = next;
      _lockInput = false;
      // 换人且无棋子迁移：掷骰方跳过回合（无可动棋子，或三 6 惩罚
      // 无可罚棋子），观战端同样给出提示，文案与本地统一
      if (next.currentPlayer != prev.currentPlayer && !next.gameOver) {
        _hint('无可动棋子，跳过回合', context.palette.textSecondary);
      }
      return;
    }
    final List<Point<double>> path;
    if (penalty) {
      // 三 6 惩罚：最后移动的棋子直线飞回停机坪机位
      path = [
        planeCoord(prev, movedPlane.$1, movedPlane.$2),
        planeCoord(next, movedPlane.$1, movedPlane.$2),
      ];
    } else {
      final inferred = _inferMove(prev, next, movedPlane);
      path = inferred == null
          ? [
              planeCoord(prev, movedPlane.$1, movedPlane.$2),
              planeCoord(next, movedPlane.$1, movedPlane.$2),
            ]
          : buildMovePath(
              state: prev,
              move: inferred.move,
              dice: inferred.dice,
              newState: next,
            );
    }
    _pendingTo = next;
    _selected = null;
    _lockInput = true;
    _animator.start(
      plane: movedPlane,
      path: path,
      capturedFlights: capturedFlights,
      onCompleted: () {
        if (!mounted) return;
        setState(() {
          _display = next;
          _lockInput = false;
        });
        if (next.gameOver) {
          if (_pendingWinDialog) {
            _pendingWinDialog = false;
            _showWinDialog();
          }
          return;
        }
        if (penalty) {
          _hint('连续三个 6！最后移动的飞机返回停机坪', AeroplaneColors.yellow);
        } else if (next.currentPlayer == mover) {
          _hint('奖励再掷一次', context.palette.primary);
        }
      },
    );
  }

  /// 由迁移前后状态重放推断实际走法与骰点（与房主同源的引擎逐骰点
  /// 试探，供逐格动画路径推导）；快照必然对应一次合法迁移，理论必命中，
  /// 未命中返回 null（调用方退化为直线滑行）
  ({AeroplaneMove move, int dice})? _inferMove(
    AeroplaneGameState prev,
    AeroplaneGameState next,
    (AeroplaneColor, int) planeKey,
  ) {
    final target = next.planesOf(planeKey.$1)[planeKey.$2];
    for (var dice = 1; dice <= 6; dice++) {
      if (AeroplaneEngine.isThirdSixPenalty(prev, dice)) continue;
      for (final move in AeroplaneEngine.legalMoves(prev, dice)) {
        if (move.color != planeKey.$1 || move.planeId != planeKey.$2) continue;
        final applied = AeroplaneEngine.applyMove(prev, move, dice);
        if (applied.planesOf(planeKey.$1)[planeKey.$2] == target) {
          return (move: move, dice: dice);
        }
      }
    }
    return null;
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
  // 玩家交互
  // ---------------------------------------------------------------------------

  /// 点击「掷骰子」：交控制器掷骰（房主本地生成 / 客户端发请求），
  /// 骰面翻动由新骰点广播统一驱动（见 [_onControllerChanged]）
  void _roll() {
    final controller = _controller;
    if (controller == null) return;
    if (!controller.rollDice()) return;
    setState(() => _selected = null);
  }

  /// 骰面快速翻动后定格到广播结果（[result] 为本次权威骰点）
  void _startRollAnimation(int result) {
    setState(() {
      _rolling = true;
      _selected = null;
    });
    var ticks = 0;
    _rollTimer?.cancel();
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
      setState(() {
        _rolling = false;
        _dice = result;
      });
    });
  }

  /// 点击可动棋子：选中（确认行显示「取消/下棋」）
  void _onPlaneTap(AeroplaneColor color, int planeId) {
    final controller = _controller;
    if (controller == null) return;
    if (!_movable(controller).contains((color, planeId))) return;
    setState(() => _selected = (color, planeId));
  }

  /// 确认走子：交控制器提交房主裁决（选中棋子存在飞越变体时一律飞越，
  /// 与本地口径一致）；成功后锁输入等待快照同步
  void _confirmMove(AeroplaneOnlineController controller) {
    final selected = _selected;
    final state = controller.state;
    final dice = controller.pendingDice;
    if (selected == null || state == null || dice == null) return;
    if (AeroplaneEngine.isThirdSixPenalty(state, dice)) return;
    final moves = AeroplaneEngine.legalMoves(state, dice)
        .where((m) => m.color == selected.$1 && m.planeId == selected.$2)
        .toList();
    if (moves.isEmpty) return;
    final move = moves.firstWhere((m) => m.fly, orElse: () => moves.first);
    if (controller.submitMove(move.planeId, fly: move.fly)) {
      setState(() => _selected = null);
    }
  }

  // ---------------------------------------------------------------------------
  // 交互可用性（随控制器状态与页面动画状态推导）
  // ---------------------------------------------------------------------------

  bool _canRoll(AeroplaneOnlineController controller) =>
      controller.isMyTurn &&
      controller.pendingDice == null &&
      !_rolling &&
      !_lockInput &&
      !_animator.animating;

  Set<(AeroplaneColor, int)> _movable(AeroplaneOnlineController controller) {
    final state = controller.state;
    final dice = controller.pendingDice;
    if (state == null ||
        dice == null ||
        !controller.isMyTurn ||
        _rolling ||
        _lockInput ||
        _animator.animating) {
      return const {};
    }
    // 三 6 惩罚回合不走子（惩罚快照即将到达）
    if (AeroplaneEngine.isThirdSixPenalty(state, dice)) return const {};
    return {
      for (final move in AeroplaneEngine.legalMoves(state, dice))
        (move.color, move.planeId),
    };
  }

  // ---------------------------------------------------------------------------
  // 终局
  // ---------------------------------------------------------------------------

  /// 胜负终局弹窗（无胜负终止走骨架通用弹窗）；延迟标记的弹窗在
  /// 终局动画完成后经 [_applyTransition] 回调触发
  bool _onGameEvent(AeroplaneOnlineController controller, VoidCallback _) {
    if (_winDialogShown || controller.winnerSeat == null) return false;
    _winDialogShown = true;
    if (_animator.animating) {
      _pendingWinDialog = true;
    } else {
      _showWinDialog();
    }
    return false;
  }

  Future<void> _showWinDialog() async {
    final controller = _controller;
    final winner = controller?.state?.winner;
    if (controller == null || winner == null) return;
    await showBoardGameWinDialog(
      context,
      winner: '${winner.label}方',
      message: controller.myColor == winner
          ? '4 架飞机全部抵达终点，你获得胜利'
          : '4 架飞机全部抵达终点',
      onExit: () {
        if (mounted) exitPageClean(context);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 视图
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return OnlineGamePageShell<AeroplaneOnlineController>(
      title: '飞行棋 · 联机',
      exitMessage: '退出后将断开与房间的连接，对局将结束',
      createController: _createController,
      onControllerChanged: _onControllerChanged,
      onGameEvent: _onGameEvent,
      buildGameView: _buildGameView,
    );
  }

  Widget _buildGameView(
    BuildContext context,
    AeroplaneOnlineController controller,
    VoidCallback requestExit,
  ) {
    final state = _display ?? controller.state;
    if (state == null) {
      // 客户端等待首个快照（RoomClient 暂存回放保证不丢，纯防御）
      return const SizedBox.shrink();
    }
    final over = state.gameOver;
    final ended = over || controller.gameEndedText != null;
    final turnColor = over ? state.winner! : state.currentPlayer;
    final turnSeat = controller.seatOfColor(turnColor);
    final turnName = controller.seatNames[turnSeat];
    final String turnTitle;
    final String turnSubtitle;
    if (over) {
      turnTitle = '${turnColor.label}方胜利';
      turnSubtitle = '对局结束';
    } else if (controller.gameEndedText != null) {
      turnTitle = '对局结束';
      turnSubtitle = '本局已终止';
    } else {
      turnTitle = '${turnName ?? '玩家$turnSeat'} · ${turnColor.label}方';
      turnSubtitle = _turnSubtitle(controller);
    }
    return SizedBox.expand(
      child: Stack(
        children: [
          PageContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 回合卡：对局中提示当前行动方，终局切换为胜方展示
                TurnCard(
                  icon: over
                      ? Icons.emoji_events_rounded
                      : Icons.flight_takeoff_rounded,
                  subtitle: turnSubtitle,
                  title: turnTitle,
                  titleKey: ValueKey(turnTitle),
                ),
                const SizedBox(height: 12),
                // 棋盘独占剩余高度（贴顶满宽）：骰子若与之均分弹性空间，
                // 会把棋盘压小、两侧出现超出页边距的留白
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: AeroplaneBoardView(
                      planes: state.planes,
                      movable: _movable(controller),
                      selected: _selected,
                      moveAnim: _animator.movers,
                      onPlaneTap: _onPlaneTap,
                    ),
                  ),
                ),
                SizedBox(
                  height: 120,
                  child: Center(
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 80),
                      scale: _rolling ? 1.08 : 1.0,
                      child: _dice == null
                          ? const SizedBox.shrink()
                          : AeroplaneDice(value: _dice!),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ConfirmMoveRow(
                  visible: _selected != null,
                  onCancelMove: () => setState(() => _selected = null),
                  onConfirmMove: () => _confirmMove(controller),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: ended ? '退出对局' : '掷骰子',
                  icon: ended ? Icons.logout_rounded : Icons.casino_rounded,
                  onPressed: ended
                      ? requestExit
                      : _canRoll(controller)
                      ? _roll
                      : null,
                ),
              ],
            ),
          ),
          // 对局反馈提示覆盖层：不拦截触摸，仅做视觉提醒
          if (_hintText.isNotEmpty)
            IgnorePointer(
              child: Center(
                child: FlashHint(
                  trigger: _hintTrigger,
                  text: _hintText,
                  accentColor: _hintColor,
                  fontSize: 30,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 回合卡副标题：按是否轮到自己与掷骰进度区分提示对象
  String _turnSubtitle(AeroplaneOnlineController controller) {
    if (!controller.isMyTurn) return '等待对方行动';
    return controller.pendingDice == null ? '轮到你掷骰子' : '轮到你走子';
  }
}
