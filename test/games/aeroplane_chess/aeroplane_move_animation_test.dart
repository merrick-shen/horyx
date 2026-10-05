import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_board.dart';
import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';
import 'package:horyx/games/aeroplane_chess/services/aeroplane_engine.dart';
import 'package:horyx/games/aeroplane_chess/widgets/aeroplane_move_animation.dart';

/// 走子动画路径构建测试（本地页与联机页共用的纯函数）
/// 用引擎构造真实迁移，断言路径停留点序列与规则动效一致：
/// 逐格推进、跳跃/回退后的收尾滑行、飞越的直线插值、终点飞回基地
void main() {
  const players = [
    AeroplanePlayer(color: AeroplaneColor.green, name: '玩家1'),
    AeroplanePlayer(color: AeroplaneColor.red, name: '玩家2'),
    AeroplanePlayer(color: AeroplaneColor.blue, name: '玩家3'),
    AeroplanePlayer(color: AeroplaneColor.yellow, name: '玩家4'),
  ];

  AeroplaneGameState state(
    Map<AeroplaneColor, List<PlanePosition>> planes, {
    AeroplaneColor current = AeroplaneColor.red,
  }) => AeroplaneGameState(
    players: players,
    planes: planes,
    currentPlayer: current,
    consecutiveSixes: 0,
    gameOver: false,
    winner: null,
    savedAt: DateTime(2026),
  );

  Map<AeroplaneColor, List<PlanePosition>> allInHangar() => {
    for (final color in AeroplaneColor.values)
      color: [
        for (var i = 0; i < 4; i++) PlanePosition(zone: PlaneZone.hangar, index: i),
      ],
  };

  /// 红方棋子 0 的单子位置覆盖（其余棋子全部停机坪）
  Map<AeroplaneColor, List<PlanePosition>> redPlane0(PlanePosition pos) =>
      allInHangar()..[AeroplaneColor.red]![0] = pos;

  test('起飞走法：停机坪直达准备区两点', () {
    final from = state(redPlane0(PlanePosition(zone: PlaneZone.hangar, index: 0)));
    const move = AeroplaneMove(color: AeroplaneColor.red, planeId: 0);
    final to = AeroplaneEngine.applyMove(from, move, 6);
    expect(to.planesOf(AeroplaneColor.red)[0].zone, PlaneZone.ready);

    final path = buildMovePath(state: from, move: move, dice: 6, newState: to);
    expect(path, [
      AeroplaneBoard.hangarSlotCenter(AeroplaneColor.red, 0),
      AeroplaneBoard.readyCellCenter(AeroplaneColor.red),
    ]);
  });

  test('准备区出发：逐格踏上跑道（起飞格为第 1 步）', () {
    final from = state(redPlane0(PlanePosition(zone: PlaneZone.ready, index: 0)));
    const move = AeroplaneMove(color: AeroplaneColor.red, planeId: 0);
    final to = AeroplaneEngine.applyMove(from, move, 3);
    // 掷 3 → 起飞格为第 1 步，落在第 3 格（累计步数 2，外环 index 6）
    expect(to.planesOf(AeroplaneColor.red)[0],
        PlanePosition(zone: PlaneZone.ring, index: 6));

    final path = buildMovePath(state: from, move: move, dice: 3, newState: to);
    expect(path, [
      AeroplaneBoard.readyCellCenter(AeroplaneColor.red),
      AeroplaneBoard.ringAnchor(4),
      AeroplaneBoard.ringAnchor(5),
      AeroplaneBoard.ringAnchor(6),
    ]);
  });

  test('普通行进逐格推进', () {
    final from = state(redPlane0(PlanePosition(zone: PlaneZone.ring, index: 4)));
    const move = AeroplaneMove(color: AeroplaneColor.red, planeId: 0);
    final to = AeroplaneEngine.applyMove(from, move, 1);
    expect(to.planesOf(AeroplaneColor.red)[0],
        PlanePosition(zone: PlaneZone.ring, index: 5));

    final path = buildMovePath(state: from, move: move, dice: 1, newState: to);
    expect(path, [AeroplaneBoard.ringAnchor(4), AeroplaneBoard.ringAnchor(5)]);
  });

  test('落己色格跳跃：逐格至落点后一次滑到跳跃落点', () {
    // 红方起飞格 4 前进 4 步落 ring 8（红格），顺跳至 ring 12
    final from = state(redPlane0(PlanePosition(zone: PlaneZone.ring, index: 4)));
    const move = AeroplaneMove(color: AeroplaneColor.red, planeId: 0);
    final to = AeroplaneEngine.applyMove(from, move, 4);
    expect(to.planesOf(AeroplaneColor.red)[0],
        PlanePosition(zone: PlaneZone.ring, index: 12));

    final path = buildMovePath(state: from, move: move, dice: 4, newState: to);
    expect(path, [
      AeroplaneBoard.ringAnchor(4),
      AeroplaneBoard.ringAnchor(5),
      AeroplaneBoard.ringAnchor(6),
      AeroplaneBoard.ringAnchor(7),
      AeroplaneBoard.ringAnchor(8),
      AeroplaneBoard.ringAnchor(12),
    ]);
  });

  test('超出终点：冲至跑道尽头再逐格回退', () {
    // 红方跑道 4 号格（累计步数 53），掷 4 → 57 超出 54，回退落 51（跑道 2 号格）
    final from = state(redPlane0(PlanePosition(zone: PlaneZone.runway, index: 4)));
    const move = AeroplaneMove(color: AeroplaneColor.red, planeId: 0);
    final to = AeroplaneEngine.applyMove(from, move, 4);
    expect(to.planesOf(AeroplaneColor.red)[0],
        PlanePosition(zone: PlaneZone.runway, index: 2));

    final path = buildMovePath(state: from, move: move, dice: 4, newState: to);
    expect(path, [
      AeroplaneBoard.runwayCellCenter(AeroplaneColor.red, 4),
      AeroplaneBoard.goalCellCenter(AeroplaneColor.red),
      AeroplaneBoard.runwayCellCenter(AeroplaneColor.red, 4),
      AeroplaneBoard.runwayCellCenter(AeroplaneColor.red, 3),
      AeroplaneBoard.runwayCellCenter(AeroplaneColor.red, 2),
    ]);
  });

  test('恰好抵达终点：逐格至跑道末格后飞回基地机位', () {
    // 红方跑道 4 号格掷 1 → 恰好 54 步抵终点
    final from = state(redPlane0(PlanePosition(zone: PlaneZone.runway, index: 4)));
    const move = AeroplaneMove(color: AeroplaneColor.red, planeId: 0);
    final to = AeroplaneEngine.applyMove(from, move, 1);
    expect(to.planesOf(AeroplaneColor.red)[0].zone, PlaneZone.goal);

    final path = buildMovePath(state: from, move: move, dice: 1, newState: to);
    expect(path, [
      AeroplaneBoard.runwayCellCenter(AeroplaneColor.red, 4),
      AeroplaneBoard.goalCellCenter(AeroplaneColor.red),
      AeroplaneBoard.hangarSlotCenter(AeroplaneColor.red, 0),
    ]);
  });

  test('加油站飞越：逐格至航线起点、直线插值飞至落点、接跳跃收尾', () {
    // 红方 ring 19（累计步数 15）掷 1 恰落加油站起点 ring 20，
    // 飞越至 landing ring 32（累计步数 28），落点为红格再接跳跃至 ring 36
    final from = state(redPlane0(PlanePosition(zone: PlaneZone.ring, index: 19)));
    const move = AeroplaneMove(color: AeroplaneColor.red, planeId: 0, fly: true);
    final to = AeroplaneEngine.applyMove(from, move, 1);
    expect(to.planesOf(AeroplaneColor.red)[0],
        PlanePosition(zone: PlaneZone.ring, index: 36));

    final path = buildMovePath(state: from, move: move, dice: 1, newState: to);
    final landing = AeroplaneBoard.ringAnchor(32);
    final start = AeroplaneBoard.ringAnchor(20);
    // 飞越段为起点到落点的 1/4、2/4、3/4 直线插值（落点本身被跳跃收尾点替代）
    final interpolations = [
      for (var i = 1; i <= 3; i++)
        Point(
          start.x + (landing.x - start.x) * (i / 4),
          start.y + (landing.y - start.y) * (i / 4),
        ),
    ];
    expect(path, [
      AeroplaneBoard.ringAnchor(19),
      start,
      ...interpolations,
      AeroplaneBoard.ringAnchor(36),
    ]);
  });
}
