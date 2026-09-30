import 'package:horyx/games/aeroplane_chess/models/aeroplane_board.dart';
import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';

/// 走法类型
enum AeroplaneMoveType { takeoff, advance }

/// 一步走法：颜色 + 棋子编号（0..3）+ 是否执行加油站飞越
/// 走法类型由棋子当前区域推导（停机坪 → 起飞，其余 → 行进）；
/// 给定骰点后落点由拓扑与连锁规则唯一确定，[fly] 仅用于区分
/// 恰好落在己方加油站起点格时「飞越 / 不飞越」的两个走法变体
class AeroplaneMove {
  const AeroplaneMove({
    required this.color,
    required this.planeId,
    this.fly = false,
  });

  final AeroplaneColor color;

  /// 棋子编号（状态中该颜色 planes 列表的下标）
  final int planeId;

  /// 是否沿加油站虚线航线飞越
  final bool fly;

  AeroplaneMoveType typeOf(AeroplaneGameState state) =>
      state.planesOf(color)[planeId].zone == PlaneZone.hangar
          ? AeroplaneMoveType.takeoff
          : AeroplaneMoveType.advance;

  @override
  bool operator ==(Object other) =>
      other is AeroplaneMove &&
      other.color == color &&
      other.planeId == planeId &&
      other.fly == fly;

  @override
  int get hashCode => Object.hash(color, planeId, fly);
}

/// 单次迁移的连锁解析结果
class _MoveChain {
  const _MoveChain({
    required this.finalSteps,
    required this.captured,
    required this.hasFlightChoice,
  });

  /// 行动棋子最终位置的累计步数
  final int finalSteps;

  /// 被撞回停机坪的棋子（颜色, 编号）
  final List<(AeroplaneColor, int)> captured;

  /// 迁移链是否落在己方加油站起点格（存在飞越与否两个走法变体）
  final bool hasFlightChoice;
}

/// 飞行棋规则引擎
///
/// 纯静态逻辑，输入 (状态, 骰点) 输出「合法走法列表」或「迁移后状态」，
/// 本地与联机共用同源判定。棋子行程以「自起飞格起的累计步数」统一表达：
/// 0 = 起飞格，entrySteps = 跑道入口格，之后依次为 6 格跑道，totalSteps = 终点；
/// 到达己方入口后必转入跑道，不继续绕环。
/// 单次迁移内收敛全部连锁效果，全程至多一次飞越 + 一次跳跃：
/// - 超出终点的步数从跑道尽头回退；
/// - 落在己色外环格顺跳至下一同色格（起飞格与入口格除外，自动触发）；
/// - 恰好落在己方加油站起点格时可选飞越，穿越敌方跑道时撞回其上敌机，
///   飞越落点可再接一次跳跃；
/// - 落点撞子：己色格对格主安全、对他色不保护，叠子整体送回，
///   被撞棋子分配最低空闲机位。
/// 连 6 计数、再掷奖励与终局判定暂未接入（当前每次迁移后直接换人）。
abstract final class AeroplaneEngine {
  /// 起飞所需骰点（已确认变体：2/4/6）
  static const Set<int> takeoffDice = {2, 4, 6};

  /// 起飞格到跑道入口格的步数（外环行进段长度）
  static int entrySteps(AeroplaneColor color) =>
      (AeroplaneBoard.runwayEntryIndex[color]! -
          AeroplaneBoard.takeoffIndex[color]!) %
      AeroplaneBoard.ringSize;

  /// 起飞格到终点的总步数（恰好抵达所需步数）
  static int totalSteps(AeroplaneColor color) =>
      entrySteps(color) + AeroplaneBoard.runwaySize + 1;

  /// 合法走法枚举：当前行动方每架可动棋子一条走法；
  /// 走法链落在己方加油站起点格时追加「飞越」变体
  static List<AeroplaneMove> legalMoves(AeroplaneGameState state, int dice) {
    _checkDice(dice);
    final color = state.currentPlayer;
    final moves = <AeroplaneMove>[];
    for (var planeId = 0; planeId < AeroplaneBoard.hangarSlots; planeId++) {
      if (!_canMove(state, color, planeId, dice)) {
        continue;
      }
      moves.add(AeroplaneMove(color: color, planeId: planeId));
      if (_resolve(state, color, planeId, dice, false).hasFlightChoice) {
        moves.add(AeroplaneMove(color: color, planeId: planeId, fly: true));
      }
    }
    return moves;
  }

  /// 执行走法：完成连锁迁移并换人
  static AeroplaneGameState applyMove(
    AeroplaneGameState state,
    AeroplaneMove move,
    int dice,
  ) {
    _checkDice(dice);
    if (move.color != state.currentPlayer) {
      throw ArgumentError('走法颜色与当前行动方不符');
    }
    if (move.planeId < 0 || move.planeId >= AeroplaneBoard.hangarSlots) {
      throw ArgumentError('棋子编号越界: ${move.planeId}');
    }
    if (!legalMoves(state, dice).contains(move)) {
      throw ArgumentError(
        '该走法不合法: 棋子 ${move.planeId} 骰点 $dice${move.fly ? '（飞越）' : ''}',
      );
    }
    final chain = _resolve(state, move.color, move.planeId, dice, move.fly);
    final planes = <AeroplaneColor, List<PlanePosition>>{
      for (final entry in state.planes.entries) entry.key: [...entry.value],
    };
    planes[move.color]![move.planeId] =
        _positionAtSteps(move.color, chain.finalSteps);
    _sendCapturedToHangar(planes, chain.captured);
    return _nextState(state, planes: planes);
  }

  /// 无可动棋子时跳过回合换人
  static AeroplaneGameState skipTurn(AeroplaneGameState state) =>
      _nextState(state);

  /// 棋子当前累计步数（仅接受外环/跑道位置；终点棋子不可动，不参与计算）
  static int journeySteps(AeroplaneColor color, PlanePosition pos) {
    switch (pos.zone) {
      case PlaneZone.ring:
        final steps =
            (pos.index - AeroplaneBoard.takeoffIndex[color]!) %
                AeroplaneBoard.ringSize;
        if (steps > entrySteps(color)) {
          throw ArgumentError('棋子位于不可达外环格: ${pos.index}');
        }
        return steps;
      case PlaneZone.runway:
        return entrySteps(color) + 1 + pos.index;
      case PlaneZone.hangar:
        throw ArgumentError('停机坪棋子无行进步数');
      case PlaneZone.goal:
        return totalSteps(color);
    }
  }

  /// 累计步数 → 棋子位置
  static PlanePosition _positionAtSteps(AeroplaneColor color, int steps) {
    final entry = entrySteps(color);
    if (steps <= entry) {
      return PlanePosition(
        zone: PlaneZone.ring,
        index:
            (AeroplaneBoard.takeoffIndex[color]! + steps) %
                AeroplaneBoard.ringSize,
      );
    }
    final runwayIndex = steps - entry - 1;
    if (runwayIndex < AeroplaneBoard.runwaySize) {
      return PlanePosition(zone: PlaneZone.runway, index: runwayIndex);
    }
    return PlanePosition(zone: PlaneZone.goal, index: 0);
  }

  static bool _canMove(
    AeroplaneGameState state,
    AeroplaneColor color,
    int planeId,
    int dice,
  ) {
    final zone = state.planesOf(color)[planeId].zone;
    if (zone == PlaneZone.hangar) {
      return takeoffDice.contains(dice);
    }
    // 超出终点从跑道尽头回退，外环/跑道棋子恒可动；终点棋子不可再动
    return zone != PlaneZone.goal;
  }

  /// 解析单次迁移的完整连锁：落点（含回退/跳跃/飞越）、沿途撞子、
  /// 是否存在飞越选择点；[fly] 决定选择点上是否执行飞越
  static _MoveChain _resolve(
    AeroplaneGameState state,
    AeroplaneColor color,
    int planeId,
    int dice,
    bool fly,
  ) {
    final from = state.planesOf(color)[planeId];
    var steps = from.zone == PlaneZone.hangar
        ? 0
        : journeySteps(color, from) + dice;
    if (steps > totalSteps(color)) {
      steps = 2 * totalSteps(color) - steps;
    }
    var flyUsed = false;
    var jumpUsed = false;
    var hasFlightChoice = false;
    final captured = <(AeroplaneColor, int)>[];
    final entry = entrySteps(color);
    while (true) {
      final pos = _positionAtSteps(color, steps);
      if (pos.zone != PlaneZone.ring) {
        break;
      }
      _captureOnRing(state, color, pos.index, captured);
      final route = AeroplaneBoard.flightRoutes[color]!;
      if (!flyUsed && pos.index == route.start) {
        hasFlightChoice = true;
        if (fly) {
          _captureRunwayCell(
            state,
            route.crossedColor,
            route.crossedRunwayIndex,
            captured,
          );
          steps =
              (route.landing - AeroplaneBoard.takeoffIndex[color]!) %
                  AeroplaneBoard.ringSize;
          flyUsed = true;
          continue;
        }
      }
      // 己色格顺跳：起飞格（0）与入口格（entry）除外，至多一次
      if (!jumpUsed &&
          steps > 0 &&
          steps < entry &&
          AeroplaneBoard.ringColor(pos.index) == color) {
        steps += 4;
        jumpUsed = true;
        continue;
      }
      break;
    }
    return _MoveChain(
      finalSteps: steps,
      captured: captured,
      hasFlightChoice: hasFlightChoice,
    );
  }

  /// 落点撞子：己色格对格主安全、对他色不保护，叠子整体送回
  static void _captureOnRing(
    AeroplaneGameState state,
    AeroplaneColor moverColor,
    int ringIndex,
    List<(AeroplaneColor, int)> captured,
  ) {
    final cellColor = AeroplaneBoard.ringColor(ringIndex);
    for (final entry in state.planes.entries) {
      if (entry.key == moverColor || entry.key == cellColor) {
        continue;
      }
      for (var i = 0; i < entry.value.length; i++) {
        final pos = entry.value[i];
        if (pos.zone == PlaneZone.ring && pos.index == ringIndex) {
          captured.add((entry.key, i));
        }
      }
    }
  }

  /// 飞越航线穿越敌方跑道格：其上敌机（含叠子）一律撞回，安全格不豁免
  static void _captureRunwayCell(
    AeroplaneGameState state,
    AeroplaneColor owner,
    int runwayIndex,
    List<(AeroplaneColor, int)> captured,
  ) {
    final planes = state.planesOf(owner);
    for (var i = 0; i < planes.length; i++) {
      final pos = planes[i];
      if (pos.zone == PlaneZone.runway && pos.index == runwayIndex) {
        captured.add((owner, i));
      }
    }
  }

  /// 被撞棋子送回停机坪，分配各色最低空闲机位
  static void _sendCapturedToHangar(
    Map<AeroplaneColor, List<PlanePosition>> planes,
    List<(AeroplaneColor, int)> captured,
  ) {
    final byColor = <AeroplaneColor, List<int>>{};
    for (final (color, planeId) in captured) {
      (byColor[color] ??= []).add(planeId);
    }
    for (final entry in byColor.entries) {
      final planeIds = entry.value..sort();
      final list = planes[entry.key]!;
      final usedSlots = <int>{
        for (var i = 0; i < list.length; i++)
          if (!planeIds.contains(i) && list[i].zone == PlaneZone.hangar)
            list[i].index,
      };
      var slot = 0;
      for (final planeId in planeIds) {
        while (usedSlots.contains(slot)) {
          slot++;
        }
        list[planeId] = PlanePosition(zone: PlaneZone.hangar, index: slot);
        usedSlots.add(slot);
      }
    }
  }

  /// 迁移后状态：换下一位玩家（按 players 列表轮转），连 6 计数清零
  /// （再掷奖励与三 6 惩罚接入后收敛为完整回合状态机）
  static AeroplaneGameState _nextState(
    AeroplaneGameState state, {
    Map<AeroplaneColor, List<PlanePosition>>? planes,
  }) {
    final order = state.players;
    final nextIndex =
        (order.indexWhere((p) => p.color == state.currentPlayer) + 1) %
            order.length;
    return AeroplaneGameState(
      players: state.players,
      planes: planes ?? state.planes,
      currentPlayer: order[nextIndex].color,
      consecutiveSixes: 0,
      gameOver: state.gameOver,
      winner: state.winner,
      savedAt: state.savedAt,
    );
  }

  static void _checkDice(int dice) {
    if (dice < 1 || dice > 6) {
      throw ArgumentError('骰点须为 1..6: $dice');
    }
  }
}
