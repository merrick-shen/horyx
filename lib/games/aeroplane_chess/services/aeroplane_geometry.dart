import 'dart:math';

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

/// 迁移前后状态逐枚比对，收集被撞棋子的飞回段（棋子, 起点, 终点坐标）：
/// 非行动方棋子从场上（非停机坪）变为停机坪即视为被撞；行动方回停机坪
/// 只发生在三 6 惩罚，其飞回走主路径动画。本地与联机对局页共用
List<((AeroplaneColor, int), Point<double>, Point<double>)> capturedPlaneFlights(
  AeroplaneGameState prev,
  AeroplaneGameState next, {
  required AeroplaneColor mover,
}) {
  return [
    for (final entry in prev.planes.entries)
      for (var i = 0; i < entry.value.length; i++)
        if (entry.key != mover &&
            entry.value[i].zone != PlaneZone.hangar &&
            next.planesOf(entry.key)[i].zone == PlaneZone.hangar)
          (
            (entry.key, i),
            planeCoord(prev, entry.key, i),
            planeCoord(next, entry.key, i),
          ),
  ];
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
    // 起飞直达准备区（不踏上跑道，不触发连锁）
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
