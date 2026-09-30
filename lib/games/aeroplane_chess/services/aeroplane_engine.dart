import 'package:horyx/games/aeroplane_chess/models/aeroplane_board.dart';
import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';

/// 走法类型
enum AeroplaneMoveType { takeoff, advance }

/// 一步走法：颜色 + 棋子编号（0..3）
/// 走法类型由棋子当前区域推导（停机坪 → 起飞，其余 → 行进）；
/// 给定骰点后落点由拓扑唯一确定，故无需携带目标位置
class AeroplaneMove {
  const AeroplaneMove({required this.color, required this.planeId});

  final AeroplaneColor color;

  /// 棋子编号（状态中该颜色 planes 列表的下标）
  final int planeId;

  AeroplaneMoveType typeOf(AeroplaneGameState state) =>
      state.planesOf(color)[planeId].zone == PlaneZone.hangar
          ? AeroplaneMoveType.takeoff
          : AeroplaneMoveType.advance;

  @override
  bool operator ==(Object other) =>
      other is AeroplaneMove && other.color == color && other.planeId == planeId;

  @override
  int get hashCode => Object.hash(color, planeId);
}

/// 飞行棋规则引擎——基础行进
///
/// 纯静态逻辑，输入 (状态, 骰点) 输出「合法走法列表」或「迁移后状态」，
/// 本地与联机共用同源判定。棋子行程以「自起飞格起的累计步数」统一表达：
/// 0 = 起飞格，entrySteps = 跑道入口格，之后依次为 6 格跑道，totalSteps = 终点；
/// 到达己方入口后必转入跑道，不继续绕环。
/// 同色跳跃、加油站飞越、撞子、超步回退、连 6 计数、再掷奖励与终局判定
/// 暂未接入（当前每次迁移后直接换人）。
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

  /// 合法走法枚举：当前行动方每架可动棋子一条走法
  static List<AeroplaneMove> legalMoves(AeroplaneGameState state, int dice) {
    _checkDice(dice);
    final color = state.currentPlayer;
    return [
      for (var planeId = 0; planeId < AeroplaneBoard.hangarSlots; planeId++)
        if (_canMove(state, color, planeId, dice))
          AeroplaneMove(color: color, planeId: planeId),
    ];
  }

  /// 执行走法：迁移棋子位置并换人
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
    if (!legalMoves(state, dice).any((m) => m.planeId == move.planeId)) {
      throw ArgumentError('该走法不合法: 棋子 ${move.planeId} 骰点 $dice');
    }
    final from = state.planesOf(move.color)[move.planeId];
    final target = from.zone == PlaneZone.hangar
        ? PlanePosition(
            zone: PlaneZone.ring,
            index: AeroplaneBoard.takeoffIndex[move.color]!,
          )
        : _positionAtSteps(
            move.color,
            journeySteps(move.color, from) + dice,
          );
    final planes = <AeroplaneColor, List<PlanePosition>>{
      for (final entry in state.planes.entries)
        entry.key: [
          for (var i = 0; i < entry.value.length; i++)
            entry.key == move.color && i == move.planeId
                ? target
                : entry.value[i],
        ],
    };
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
    if (zone == PlaneZone.goal) {
      return false;
    }
    return journeySteps(color, state.planesOf(color)[planeId]) + dice <=
        totalSteps(color);
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
