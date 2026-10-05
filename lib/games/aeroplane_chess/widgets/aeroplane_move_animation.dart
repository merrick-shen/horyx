import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_board.dart';
import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';
import 'package:horyx/games/aeroplane_chess/services/aeroplane_engine.dart';

/// 对局状态中的棋子 → 格子坐标（棋盘归一化坐标系，棋子层与动画共用）
Point<double> planeCoord(
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
    PlaneZone.goal => AeroplaneBoard.hangarSlotCenter(color, pos.index),
  };
}

/// 累计步数 → 格子坐标（行进途中经停点）
Point<double> stepsCoord(AeroplaneColor color, int steps) {
  final pos = AeroplaneEngine.positionAtSteps(color, steps);
  return switch (pos.zone) {
    PlaneZone.ring => AeroplaneBoard.ringAnchor(pos.index),
    PlaneZone.runway => AeroplaneBoard.runwayCellCenter(color, pos.index),
    _ => AeroplaneBoard.goalCellCenter(color),
  };
}

/// 走法迁移的动画路径（格子坐标停留点序列）：
/// 普通行进逐格推进；超出终点冲至尽头再逐格回退；跳跃/回退后跳跃
/// 一次滑到最终落点；飞越先逐格至航线起点、直线插值飞至落点，
/// 落点再接跳跃同样一次滑到最终点
List<Point<double>> buildMovePath({
  required AeroplaneGameState state,
  required AeroplaneMove move,
  required int dice,
  required AeroplaneGameState newState,
}) {
  final color = move.color;
  final old = state.planesOf(color)[move.planeId];
  final newPos = newState.planesOf(color)[move.planeId];
  final points = <Point<double>>[planeCoord(state, color, move.planeId)];
  if (old.zone == PlaneZone.hangar) {
    // 起飞直达起飞格（起飞落点不触发连锁）
    points.add(planeCoord(newState, color, move.planeId));
    return points;
  }
  final total = AeroplaneEngine.totalSteps(color);
  final finalSteps = newPos.zone == PlaneZone.goal
      ? total
      : AeroplaneEngine.journeySteps(color, newPos);
  // 准备区出发：起飞格（journey 0）为第 1 步，行进段自 journey 0 起
  // （s0 取 -1 使逐格序列包含起飞格）
  final s0 = old.zone == PlaneZone.ready
      ? -1
      : AeroplaneEngine.journeySteps(color, old);

  if (move.fly) {
    final route = AeroplaneBoard.flightRoutes[color]!;
    final startSteps =
        (route.start - AeroplaneBoard.takeoffIndex[color]!) %
        AeroplaneBoard.ringSize;
    for (var s = s0 + 1; s <= startSteps; s++) {
      points.add(stepsCoord(color, s));
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
          : planeCoord(newState, color, move.planeId),
    );
    return points;
  }

  final raw = s0 + dice;
  final forwardEnd = min(raw, total);
  for (var s = s0 + 1; s <= forwardEnd; s++) {
    points.add(stepsCoord(color, s));
  }
  if (raw > total) {
    final landSteps = 2 * total - raw;
    for (var s = total - 1; s >= landSteps; s--) {
      points.add(stepsCoord(color, s));
    }
    if (finalSteps != landSteps) {
      points.add(planeCoord(newState, color, move.planeId));
    }
  } else if (finalSteps != raw) {
    points.add(planeCoord(newState, color, move.planeId));
  }
  // 恰好抵达终点：从跑道末格飞回基地机位（动画末段）
  if (newPos.zone == PlaneZone.goal) {
    points.add(planeCoord(newState, color, move.planeId));
  }
  return points;
}

/// 走子动画器：主棋子沿路径逐段滑行（每段 140ms 匀速，经 ValueNotifier
/// 下发帧坐标，动画中仅重建移动棋子子树），被撞棋子在主棋子走完全程
/// （碰上）后直线飞回停机坪机位。本地与联机对局页共用。
/// 动画结束经 [start] 的 onCompleted 回调通知页面应用目标状态
class AeroplaneMoveAnimator {
  AeroplaneMoveAnimator({required TickerProvider vsync}) {
    _controller = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 600),
    );
    _controller.addListener(_updateMovers);
    _controller.addStatusListener(_onStatus);
  }

  late final AnimationController _controller;

  final ValueNotifier<List<(AeroplaneColor, int, Point<double>)>> _movers =
      ValueNotifier(const []);

  List<Point<double>> _path = const [];
  (AeroplaneColor, int)? _plane;
  List<((AeroplaneColor, int), Point<double>, Point<double>)>
  _capturedFlights = const [];

  /// 主棋子滑行占总时长的比例（无被撞时为 1）
  double _split = 1.0;
  VoidCallback? _onCompleted;

  /// 动画帧驱动移动棋子坐标流（供棋子层覆盖定位）
  ValueListenable<List<(AeroplaneColor, int, Point<double>)>> get movers =>
      _movers;

  bool get animating => _controller.isAnimating;

  /// 启动动画：[path] 为主棋子停留点序列，[capturedFlights] 为被撞棋子
  /// 的（棋子, 起点坐标, 终点坐标）；动画完成后回调 [onCompleted]
  void start({
    required (AeroplaneColor, int) plane,
    required List<Point<double>> path,
    List<((AeroplaneColor, int), Point<double>, Point<double>)>
    capturedFlights = const [],
    required VoidCallback onCompleted,
  }) {
    _plane = plane;
    _path = path;
    _capturedFlights = capturedFlights;
    _onCompleted = onCompleted;
    // 主棋子每段 140ms 匀速滑行（单段最短 300ms）；被撞棋子飞回 300ms
    final pathMs = max(300, 140 * (path.length - 1));
    final totalMs = pathMs + (capturedFlights.isEmpty ? 0 : 300);
    _split = capturedFlights.isEmpty ? 1.0 : pathMs / totalMs;
    _controller.duration = Duration(milliseconds: totalMs);
    _updateMoversAt(0);
    _controller.forward(from: 0);
  }

  /// 停止动画并清空移动棋子流（回退到格子定位）
  void reset() {
    _controller.stop();
    _plane = null;
    _path = const [];
    _capturedFlights = const [];
    _onCompleted = null;
    _movers.value = const [];
  }

  /// 动画帧：主棋子沿路径等时长段插值连续滑行（飞越段插值点更密、
  /// 滑速更快，表现掠过感），被撞棋子同步直线飞回停机坪机位
  void _updateMovers() => _updateMoversAt(_controller.value);

  void _updateMoversAt(double t) {
    final path = _path;
    final plane = _plane;
    if (plane == null || path.isEmpty) return;
    // 分段进度：主棋子先沿路径滑行（走到落点碰上），被撞棋子保持原位，
    // 主棋子走完全程后才进入飞回阶段
    final split = _split;
    final pathT = split >= 1 ? t : (t / split).clamp(0.0, 1.0);
    final f = pathT * (path.length - 1);
    final k = f.floor();
    final main = k >= path.length - 1
        ? path.last
        : Point(
            path[k].x + (path[k + 1].x - path[k].x) * (f - k),
            path[k].y + (path[k + 1].y - path[k].y) * (f - k),
          );
    final movers = <(AeroplaneColor, int, Point<double>)>[
      (plane.$1, plane.$2, main),
    ];
    if (_capturedFlights.isNotEmpty) {
      final returnT = split >= 1
          ? 0.0
          : ((t - split) / (1 - split)).clamp(0.0, 1.0);
      for (final (planeKey, from, to) in _capturedFlights) {
        movers.add((
          planeKey.$1,
          planeKey.$2,
          Point(
            from.x + (to.x - from.x) * returnT,
            from.y + (to.y - from.y) * returnT,
          ),
        ));
      }
    }
    _movers.value = movers;
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final done = _onCompleted;
    _onCompleted = null;
    _movers.value = const [];
    done?.call();
  }

  void dispose() {
    _controller.dispose();
    _movers.dispose();
  }
}
