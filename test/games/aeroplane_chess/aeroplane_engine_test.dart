import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_board.dart';
import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';
import 'package:horyx/games/aeroplane_chess/services/aeroplane_engine.dart';

void main() {
  final savedAt = DateTime(2026, 10, 1, 12);

  const fourPlayers = [
    AeroplanePlayer(color: AeroplaneColor.green, name: '玩家1'),
    AeroplanePlayer(color: AeroplaneColor.red, name: '玩家2'),
    AeroplanePlayer(color: AeroplaneColor.blue, name: '玩家3'),
    AeroplanePlayer(color: AeroplaneColor.yellow, name: '玩家4'),
  ];

  List<PlanePosition> allInHangar() => [
        for (var i = 0; i < 4; i++)
          PlanePosition(zone: PlaneZone.hangar, index: i),
      ];

  /// 该颜色外环行进 steps 步后的格子（0 = 起飞格）
  PlanePosition ringAtSteps(AeroplaneColor color, int steps) =>
      PlanePosition(
        zone: PlaneZone.ring,
        index: (AeroplaneBoard.takeoffIndex[color]! + steps) %
            AeroplaneBoard.ringSize,
      );

  PlanePosition runwayAt(int index) =>
      PlanePosition(zone: PlaneZone.runway, index: index);

  AeroplaneGameState buildState({
    List<AeroplanePlayer> players = fourPlayers,
    Map<AeroplaneColor, List<PlanePosition>>? planes,
    AeroplaneColor currentPlayer = AeroplaneColor.green,
    int consecutiveSixes = 0,
    (AeroplaneColor, int)? lastMoved,
    bool gameOver = false,
    AeroplaneColor? winner,
  }) {
    final colors = players.map((p) => p.color).toSet();
    return AeroplaneGameState(
      players: players,
      planes: planes ??
          {for (final c in colors) c: allInHangar()},
      currentPlayer: currentPlayer,
      consecutiveSixes: consecutiveSixes,
      lastMoved: lastMoved,
      gameOver: gameOver,
      winner: winner,
      savedAt: savedAt,
    );
  }

  group('起飞条件', () {
    test('停机坪棋子掷 2/4/6 可起飞（已确认变体）', () {
      final state = buildState();
      for (final dice in const [2, 4, 6]) {
        final moves = AeroplaneEngine.legalMoves(state, dice);
        expect(moves, hasLength(4));
        expect(
          moves.every((m) => m.typeOf(state) == AeroplaneMoveType.takeoff),
          isTrue,
        );
        expect(moves.map((m) => m.planeId), {0, 1, 2, 3});
      }
    });

    test('停机坪棋子掷 1/3/5 不可起飞，全部无可动', () {
      final state = buildState();
      for (final dice in const [1, 3, 5]) {
        expect(AeroplaneEngine.legalMoves(state, dice), isEmpty);
      }
    });

    test('起飞迁移：落到准备区，掷 6 奖励再掷且连 6 计数 +1', () {
      final state = buildState(currentPlayer: AeroplaneColor.green);
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.green, planeId: 2),
        6,
      );
      expect(
        moved.planesOf(AeroplaneColor.green)[2],
        PlanePosition(zone: PlaneZone.ready, index: 0),
      );
      expect(moved.planesOf(AeroplaneColor.green)[0].zone, PlaneZone.hangar);
      expect(moved.currentPlayer, AeroplaneColor.green);
      expect(moved.consecutiveSixes, 1);
      expect(moved.lastMoved, (AeroplaneColor.green, 2));
      expect(moved.savedAt, savedAt);
    });

    test('准备区棋子任意点数可动，掷 N 落 journey N-1（起飞格为第 1 步）', () {
      final state = buildState(
        planes: {
          AeroplaneColor.green: [
            PlanePosition(zone: PlaneZone.ready, index: 0),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.red: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
        currentPlayer: AeroplaneColor.green,
      );
      // 掷 1 也可动（落在起飞格）
      expect(AeroplaneEngine.legalMoves(state, 1), isNotEmpty);
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.green, planeId: 0),
        3,
      );
      expect(moved.planesOf(AeroplaneColor.green)[0], ringAtSteps(AeroplaneColor.green, 2));
    });
  });

  group('外环前进', () {
    test('按骰点前进，落点非己色格时不跳跃', () {
      // 红方起飞格 4，前进 3 步到 7
      final state = buildState(
        planes: {
          AeroplaneColor.red: [
            ringAtSteps(AeroplaneColor.red, 0),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.green: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
        currentPlayer: AeroplaneColor.red,
      );
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.red, planeId: 0),
        3,
      );
      expect(
        moved.planesOf(AeroplaneColor.red)[0],
        ringAtSteps(AeroplaneColor.red, 3),
      );
      expect(moved.currentPlayer, AeroplaneColor.blue);
    });

    test('落在己色格顺跳至下一个同色格（至多一次，落点撞子同样生效）', () {
      // 红 4 + 4 = 8（红色格）→ 顺跳至 12；8 与 12 上的他色棋子均被撞回
      final state = buildState(
        planes: {
          AeroplaneColor.red: [
            ringAtSteps(AeroplaneColor.red, 0),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.green: allInHangar(),
          AeroplaneColor.blue: [
            PlanePosition(zone: PlaneZone.ring, index: 12),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.yellow: [
            PlanePosition(zone: PlaneZone.ring, index: 8),
            ...allInHangar().skip(1),
          ],
        },
        currentPlayer: AeroplaneColor.red,
      );
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.red, planeId: 0),
        4,
      );
      expect(
        moved.planesOf(AeroplaneColor.red)[0],
        ringAtSteps(AeroplaneColor.red, 8),
      );
      expect(
        moved.planesOf(AeroplaneColor.yellow)[0],
        PlanePosition(zone: PlaneZone.hangar, index: 0),
      );
      expect(
        moved.planesOf(AeroplaneColor.blue)[0],
        PlanePosition(zone: PlaneZone.hangar, index: 0),
      );
      // 跳跃触发再掷奖励，行动方不变；掷非 6 连 6 计数清零
      expect(moved.currentPlayer, AeroplaneColor.red);
      expect(moved.consecutiveSixes, 0);
    });
  });

  group('进跑道与跑道行进', () {
    test('跨过入口格进入跑道（入口 = 起飞后 48 步）', () {
      // 红：起飞格 4，入口 0；行进 46 步在格 50，+3 越过入口进跑道 0 号格
      final cases = [
        (46, 3, 0),
        (47, 4, 2),
        (48, 2, 1),
      ];
      for (final (steps, dice, runwayIndex) in cases) {
        final state = buildState(
          planes: {
            AeroplaneColor.red: [
              ringAtSteps(AeroplaneColor.red, steps),
              ...allInHangar().skip(1),
            ],
            AeroplaneColor.green: allInHangar(),
            AeroplaneColor.blue: allInHangar(),
            AeroplaneColor.yellow: allInHangar(),
          },
          currentPlayer: AeroplaneColor.red,
        );
        final moved = AeroplaneEngine.applyMove(
          state,
          const AeroplaneMove(color: AeroplaneColor.red, planeId: 0),
          dice,
        );
        expect(
          moved.planesOf(AeroplaneColor.red)[0],
          runwayAt(runwayIndex),
          reason: '行进 $steps 步 +$dice 应进跑道 $runwayIndex 号格',
        );
      }
    });

    test('跑道内按骰点前进', () {
      final state = buildState(
        planes: {
          AeroplaneColor.red: [
            runwayAt(1),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.green: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
        currentPlayer: AeroplaneColor.red,
      );
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.red, planeId: 0),
        3,
      );
      expect(moved.planesOf(AeroplaneColor.red)[0], runwayAt(4));
    });

    test('恰好步数抵达终点', () {
      // 跑道 4 号格 = 行进 53 步，+1 恰好 54 步到终点（跑道末格）；跑道 3 +2 同理
      final cases = [(4, 1), (3, 2)];
      for (final (runwayIndex, dice) in cases) {
        final state = buildState(
          planes: {
            AeroplaneColor.red: [
              runwayAt(runwayIndex),
              ...allInHangar().skip(1),
            ],
            AeroplaneColor.green: allInHangar(),
            AeroplaneColor.blue: allInHangar(),
            AeroplaneColor.yellow: allInHangar(),
          },
          currentPlayer: AeroplaneColor.red,
        );
        final moved = AeroplaneEngine.applyMove(
          state,
          const AeroplaneMove(color: AeroplaneColor.red, planeId: 0),
          dice,
        );
        expect(
          moved.planesOf(AeroplaneColor.red)[0],
          PlanePosition(zone: PlaneZone.goal, index: 0),
          reason: '跑道 $runwayIndex +$dice 应恰好抵达终点',
        );
      }
    });

    test('入口格不触发跳跃（含跳跃恰好落入入口格）', () {
      // 红：行进 47 步 +1 直落入口；或行进 43 步 +1 落己色格跳至入口后不再跳
      final cases = [(47, 1), (43, 1)];
      for (final (steps, dice) in cases) {
        final state = buildState(
          planes: {
            AeroplaneColor.red: [
              ringAtSteps(AeroplaneColor.red, steps),
              ...allInHangar().skip(1),
            ],
            AeroplaneColor.green: allInHangar(),
            AeroplaneColor.blue: allInHangar(),
            AeroplaneColor.yellow: allInHangar(),
          },
          currentPlayer: AeroplaneColor.red,
        );
        final moved = AeroplaneEngine.applyMove(
          state,
          const AeroplaneMove(color: AeroplaneColor.red, planeId: 0),
          dice,
        );
        expect(
          moved.planesOf(AeroplaneColor.red)[0],
          PlanePosition(zone: PlaneZone.ring, index: 0),
          reason: '行进 $steps 步 +$dice 应停在入口格',
        );
      }
    });

    test('超出终点从跑道尽头回退', () {
      // 跑道 4 号格 = 行进 53 步，+5 超出 4 格回退至 50（跑道 1 号格）；
      // 跑道 3 +5 超出 3 格回退至 51（跑道 2 号格）
      final cases = [(4, 5, 1), (3, 5, 2)];
      for (final (runwayIndex, dice, expected) in cases) {
        final state = buildState(
          planes: {
            AeroplaneColor.red: [
              runwayAt(runwayIndex),
              ...allInHangar().skip(1),
            ],
            AeroplaneColor.green: allInHangar(),
            AeroplaneColor.blue: allInHangar(),
            AeroplaneColor.yellow: allInHangar(),
          },
          currentPlayer: AeroplaneColor.red,
        );
        expect(AeroplaneEngine.legalMoves(state, dice), isNotEmpty);
        final moved = AeroplaneEngine.applyMove(
          state,
          const AeroplaneMove(color: AeroplaneColor.red, planeId: 0),
          dice,
        );
        expect(
          moved.planesOf(AeroplaneColor.red)[0],
          runwayAt(expected),
          reason: '跑道 $runwayIndex +$dice 应回退至跑道 $expected 号格',
        );
      }
    });
  });

  group('无可动跳过', () {
    test('全部棋子无可动时走法列表为空，跳过换人并清零连 6', () {
      final state = buildState(
        currentPlayer: AeroplaneColor.green,
        consecutiveSixes: 2,
      );
      expect(AeroplaneEngine.legalMoves(state, 1), isEmpty);
      final skipped = AeroplaneEngine.skipTurn(state);
      expect(skipped.currentPlayer, AeroplaneColor.red);
      expect(skipped.consecutiveSixes, 0);
      expect(skipped.planes, state.planes);
    });

    test('全部棋子抵达终点后无可动，跳过换人', () {
      final state = buildState(
        planes: {
          AeroplaneColor.red: [
            for (var i = 0; i < 4; i++)
              PlanePosition(zone: PlaneZone.goal, index: 0),
          ],
          AeroplaneColor.green: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
        currentPlayer: AeroplaneColor.red,
      );
      expect(AeroplaneEngine.legalMoves(state, 6), isEmpty);
      final skipped = AeroplaneEngine.skipTurn(state);
      expect(skipped.currentPlayer, AeroplaneColor.blue);
    });

    test('已抵达终点的棋子不再产生走法', () {
      final state = buildState(
        planes: {
          AeroplaneColor.red: [
            PlanePosition(zone: PlaneZone.goal, index: 0),
            runwayAt(4),
            allInHangar()[2],
            allInHangar()[3],
          ],
          AeroplaneColor.green: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
        currentPlayer: AeroplaneColor.red,
      );
      final moves = AeroplaneEngine.legalMoves(state, 1);
      expect(moves, [const AeroplaneMove(color: AeroplaneColor.red, planeId: 1)]);
    });
  });

  group('换人流转', () {
    test('按 players 列表顺序轮转并循环回首位', () {
      final yellowState = buildState(
        planes: {
          AeroplaneColor.green: allInHangar(),
          AeroplaneColor.red: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: [
            ringAtSteps(AeroplaneColor.yellow, 0),
            ...allInHangar().skip(1),
          ],
        },
        currentPlayer: AeroplaneColor.yellow,
      );
      final moved = AeroplaneEngine.applyMove(
        yellowState,
        const AeroplaneMove(color: AeroplaneColor.yellow, planeId: 0),
        2,
      );
      expect(moved.currentPlayer, AeroplaneColor.green);
    });

    test('2 人对角局按列表顺序轮转', () {
      final twoPlayers = const [
        AeroplanePlayer(color: AeroplaneColor.red, name: '玩家1'),
        AeroplanePlayer(color: AeroplaneColor.yellow, name: '玩家2'),
      ];
      final state = buildState(
        players: twoPlayers,
        planes: {
          AeroplaneColor.red: [
            ringAtSteps(AeroplaneColor.red, 0),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.yellow: allInHangar(),
        },
        currentPlayer: AeroplaneColor.red,
      );
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.red, planeId: 0),
        3,
      );
      expect(moved.currentPlayer, AeroplaneColor.yellow);
    });
  });

  group('撞子与安全格', () {
    test('落点撞回他色棋子（含叠子），格主色棋子安全豁免', () {
      // 红 4 + 3 = 7（绿色格）：绿机（格主）安全，黄机叠子两架被撞回
      final state = buildState(
        planes: {
          AeroplaneColor.red: [
            ringAtSteps(AeroplaneColor.red, 0),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.green: [
            PlanePosition(zone: PlaneZone.ring, index: 7),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: [
            PlanePosition(zone: PlaneZone.ring, index: 7),
            PlanePosition(zone: PlaneZone.ring, index: 7),
            ...allInHangar().skip(2),
          ],
        },
        currentPlayer: AeroplaneColor.red,
      );
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.red, planeId: 0),
        3,
      );
      expect(
        moved.planesOf(AeroplaneColor.red)[0],
        ringAtSteps(AeroplaneColor.red, 3),
      );
      expect(
        moved.planesOf(AeroplaneColor.green)[0],
        PlanePosition(zone: PlaneZone.ring, index: 7),
      );
      expect(
        moved.planesOf(AeroplaneColor.yellow)[0],
        PlanePosition(zone: PlaneZone.hangar, index: 0),
      );
      expect(
        moved.planesOf(AeroplaneColor.yellow)[1],
        PlanePosition(zone: PlaneZone.hangar, index: 1),
      );
      expect(
        moved.planesOf(AeroplaneColor.yellow)[2],
        PlanePosition(zone: PlaneZone.hangar, index: 2),
      );
    });

    test('准备区出发撞回起飞格上的敌机（起飞格为第 1 步）', () {
      final state = buildState(
        planes: {
          AeroplaneColor.green: [
            PlanePosition(zone: PlaneZone.ready, index: 0),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.red: allInHangar(),
          AeroplaneColor.blue: [
            PlanePosition(zone: PlaneZone.ring, index: 43),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.yellow: allInHangar(),
        },
      );
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.green, planeId: 0),
        1,
      );
      expect(
        moved.planesOf(AeroplaneColor.green)[0],
        ringAtSteps(AeroplaneColor.green, 0),
      );
      expect(
        moved.planesOf(AeroplaneColor.blue)[0],
        PlanePosition(zone: PlaneZone.hangar, index: 0),
      );
    });
  });

  group('加油站飞越', () {
    test('恰好落在航线起点格时枚举飞越与否两个走法', () {
      // 绿方航线起点 ring 7 = 行进 16 步；行进 15 步 +1 恰好落上
      final state = buildState(
        planes: {
          AeroplaneColor.green: [
            ringAtSteps(AeroplaneColor.green, 15),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.red: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
      );
      final moves = AeroplaneEngine.legalMoves(state, 1);
      expect(
        moves,
        unorderedEquals([
          const AeroplaneMove(color: AeroplaneColor.green, planeId: 0),
          const AeroplaneMove(color: AeroplaneColor.green, planeId: 0, fly: true),
        ]),
      );
    });

    test('不飞越：起点格按跳跃规则顺跳一次', () {
      final state = buildState(
        planes: {
          AeroplaneColor.green: [
            ringAtSteps(AeroplaneColor.green, 15),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.red: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
      );
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.green, planeId: 0),
        1,
      );
      expect(
        moved.planesOf(AeroplaneColor.green)[0],
        ringAtSteps(AeroplaneColor.green, 20),
      );
    });

    test('飞越后落点接一次跳跃（一次飞跃+一次跳跃上限）', () {
      final state = buildState(
        planes: {
          AeroplaneColor.green: [
            ringAtSteps(AeroplaneColor.green, 15),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.red: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
      );
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.green, planeId: 0, fly: true),
        1,
      );
      // 飞越至落点（行进 28 步）后顺跳一次至 32，不再连跳
      expect(
        moved.planesOf(AeroplaneColor.green)[0],
        ringAtSteps(AeroplaneColor.green, 32),
      );
    });

    test('飞越撞回被穿越跑道上的敌机（跑道安全格不豁免）', () {
      final state = buildState(
        planes: {
          AeroplaneColor.green: [
            ringAtSteps(AeroplaneColor.green, 15),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.red: allInHangar(),
          AeroplaneColor.blue: [
            runwayAt(2),
            runwayAt(1),
            ...allInHangar().skip(2),
          ],
          AeroplaneColor.yellow: allInHangar(),
        },
      );
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.green, planeId: 0, fly: true),
        1,
      );
      // 被穿越格（蓝跑道 2 号）上的棋子送回最低空闲机位，相邻跑道格不受影响
      expect(
        moved.planesOf(AeroplaneColor.blue)[0],
        PlanePosition(zone: PlaneZone.hangar, index: 0),
      );
      expect(moved.planesOf(AeroplaneColor.blue)[1], runwayAt(1));
      expect(
        moved.planesOf(AeroplaneColor.green)[0],
        ringAtSteps(AeroplaneColor.green, 32),
      );
    });

    test('穿越格上的叠子整体送回', () {
      final state = buildState(
        planes: {
          AeroplaneColor.green: [
            ringAtSteps(AeroplaneColor.green, 15),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.red: allInHangar(),
          AeroplaneColor.blue: [
            runwayAt(2),
            runwayAt(2),
            ...allInHangar().skip(2),
          ],
          AeroplaneColor.yellow: allInHangar(),
        },
      );
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.green, planeId: 0, fly: true),
        1,
      );
      expect(
        moved.planesOf(AeroplaneColor.blue)[0],
        PlanePosition(zone: PlaneZone.hangar, index: 0),
      );
      expect(
        moved.planesOf(AeroplaneColor.blue)[1],
        PlanePosition(zone: PlaneZone.hangar, index: 1),
      );
    });

    test('三人局飞越：穿越色未参与对局时无子可撞且不崩溃', () {
      // 三人局默认色 绿红蓝，红方航线穿越黄色（未参与）跑道
      final state = buildState(
        players: fourPlayers.take(3).toList(),
        currentPlayer: AeroplaneColor.red,
        planes: {
          AeroplaneColor.green: allInHangar(),
          AeroplaneColor.red: [
            ringAtSteps(AeroplaneColor.red, 15),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.blue: allInHangar(),
        },
      );
      const move = AeroplaneMove(color: AeroplaneColor.red, planeId: 0, fly: true);
      expect(AeroplaneEngine.legalMoves(state, 1), contains(move));
      final moved = AeroplaneEngine.applyMove(state, move, 1);
      // 落点（行进 28 步）为己色格接一次跳跃至行进 32 步
      expect(
        moved.planesOf(AeroplaneColor.red)[0],
        ringAtSteps(AeroplaneColor.red, 32),
      );
    });

    test('跳跃落点为航线起点格时可接飞越（上限内不再跳跃）', () {
      // 红方航线起点 ring 20 = 行进 16 步；行进 11 步 +1 落己色格跳至起点
      final state = buildState(
        planes: {
          AeroplaneColor.red: [
            ringAtSteps(AeroplaneColor.red, 11),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.green: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
        currentPlayer: AeroplaneColor.red,
      );
      final moves = AeroplaneEngine.legalMoves(state, 1);
      expect(moves, hasLength(2));
      final noFly = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.red, planeId: 0),
        1,
      );
      expect(
        noFly.planesOf(AeroplaneColor.red)[0],
        ringAtSteps(AeroplaneColor.red, 16),
      );
      final fly = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.red, planeId: 0, fly: true),
        1,
      );
      // 跳跃已用，飞越落点不再接跳
      expect(
        fly.planesOf(AeroplaneColor.red)[0],
        ringAtSteps(AeroplaneColor.red, 28),
      );
    });

    test('未经枚举的飞越走法抛错', () {
      // 绿机落己色格仅触发跳跃，无飞越选择点
      final state = buildState(
        planes: {
          AeroplaneColor.green: [
            ringAtSteps(AeroplaneColor.green, 3),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.red: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
      );
      expect(
        () => AeroplaneEngine.applyMove(
          state,
          const AeroplaneMove(color: AeroplaneColor.green, planeId: 0, fly: true),
          1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('连 6 与再掷', () {
    test('掷非 6 无触发迁移：换人且连 6 计数清零', () {
      final state = buildState(
        planes: {
          AeroplaneColor.green: [
            ringAtSteps(AeroplaneColor.green, 0),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.red: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
        consecutiveSixes: 1,
      );
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.green, planeId: 0),
        3,
      );
      expect(moved.currentPlayer, AeroplaneColor.red);
      expect(moved.consecutiveSixes, 0);
      expect(moved.lastMoved, (AeroplaneColor.green, 0));
    });

    test('起飞掷 2 不触发再掷', () {
      final moved = AeroplaneEngine.applyMove(
        buildState(),
        const AeroplaneMove(color: AeroplaneColor.green, planeId: 0),
        2,
      );
      expect(moved.currentPlayer, AeroplaneColor.red);
      expect(moved.consecutiveSixes, 0);
    });

    test('非 6 撞子奖励再掷', () {
      final state = buildState(
        planes: {
          AeroplaneColor.green: allInHangar(),
          AeroplaneColor.red: [
            ringAtSteps(AeroplaneColor.red, 0),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: [
            PlanePosition(zone: PlaneZone.ring, index: 7),
            ...allInHangar().skip(1),
          ],
        },
        currentPlayer: AeroplaneColor.red,
        consecutiveSixes: 1,
      );
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.red, planeId: 0),
        3,
      );
      expect(
        moved.planesOf(AeroplaneColor.yellow)[0],
        PlanePosition(zone: PlaneZone.hangar, index: 0),
      );
      expect(moved.currentPlayer, AeroplaneColor.red);
      expect(moved.consecutiveSixes, 0);
    });

    test('飞越奖励再掷', () {
      final state = buildState(
        planes: {
          AeroplaneColor.green: [
            ringAtSteps(AeroplaneColor.green, 15),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.red: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
      );
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.green, planeId: 0, fly: true),
        1,
      );
      expect(moved.currentPlayer, AeroplaneColor.green);
      expect(moved.consecutiveSixes, 0);
    });

    test('掷 6 撞子跳跃多触发只奖励一次，计数仅 +1', () {
      // 绿 2 + 6 = 8（绿机行进 8 步落己色格）：落点与跳跃落点上各有一架黄机
      final state = buildState(
        planes: {
          AeroplaneColor.green: [
            ringAtSteps(AeroplaneColor.green, 2),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.red: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: [
            PlanePosition(zone: PlaneZone.ring, index: 51),
            PlanePosition(zone: PlaneZone.ring, index: 3),
            ...allInHangar().skip(2),
          ],
        },
      );
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.green, planeId: 0),
        6,
      );
      expect(moved.planesOf(AeroplaneColor.green)[0], ringAtSteps(AeroplaneColor.green, 12));
      expect(
        moved.planesOf(AeroplaneColor.yellow)[0],
        PlanePosition(zone: PlaneZone.hangar, index: 0),
      );
      expect(
        moved.planesOf(AeroplaneColor.yellow)[1],
        PlanePosition(zone: PlaneZone.hangar, index: 1),
      );
      expect(moved.currentPlayer, AeroplaneColor.green);
      expect(moved.consecutiveSixes, 1);
    });

    test('连续两个 6 计数累计至 2', () {
      var state = buildState(
        planes: {
          AeroplaneColor.green: [
            ringAtSteps(AeroplaneColor.green, 0),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.red: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
      );
      final move = const AeroplaneMove(color: AeroplaneColor.green, planeId: 0);
      state = AeroplaneEngine.applyMove(state, move, 6);
      expect(state.consecutiveSixes, 1);
      state = AeroplaneEngine.applyMove(state, move, 6);
      // 第二次掷 6 落己色格顺跳一次
      expect(state.planesOf(AeroplaneColor.green)[0], ringAtSteps(AeroplaneColor.green, 16));
      expect(state.currentPlayer, AeroplaneColor.green);
      expect(state.consecutiveSixes, 2);
    });

    test('连续第 3 个 6：走法枚举抛错，惩罚后最后移动棋子回停机坪并换人', () {
      // 承接上例：绿0 行进 16 步（ring 7），已连掷两个 6
      final state = buildState(
        planes: {
          AeroplaneColor.green: [
            ringAtSteps(AeroplaneColor.green, 16),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.red: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
        consecutiveSixes: 2,
        lastMoved: (AeroplaneColor.green, 0),
      );
      expect(AeroplaneEngine.isThirdSixPenalty(state, 6), isTrue);
      expect(() => AeroplaneEngine.legalMoves(state, 6), throwsArgumentError);
      final penalized = AeroplaneEngine.applyThirdSixPenalty(state);
      expect(
        penalized.planesOf(AeroplaneColor.green)[0],
        PlanePosition(zone: PlaneZone.hangar, index: 0),
      );
      expect(penalized.currentPlayer, AeroplaneColor.red);
      expect(penalized.consecutiveSixes, 0);
      expect(AeroplaneEngine.isThirdSixPenalty(penalized, 6), isFalse);
    });

    test('惩罚豁免：最后移动棋子已抵达终点则不返回，仍换人', () {
      final state = buildState(
        planes: {
          AeroplaneColor.green: [
            PlanePosition(zone: PlaneZone.goal, index: 0),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.red: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
        consecutiveSixes: 2,
        lastMoved: (AeroplaneColor.green, 0),
      );
      final penalized = AeroplaneEngine.applyThirdSixPenalty(state);
      expect(
        penalized.planesOf(AeroplaneColor.green)[0],
        PlanePosition(zone: PlaneZone.goal, index: 0),
      );
      expect(penalized.currentPlayer, AeroplaneColor.red);
      expect(penalized.consecutiveSixes, 0);
    });

    test('计数不足时执行惩罚抛错', () {
      expect(
        () => AeroplaneEngine.applyThirdSixPenalty(buildState(consecutiveSixes: 1)),
        throwsArgumentError,
      );
      expect(
        () => AeroplaneEngine.applyThirdSixPenalty(buildState()),
        throwsArgumentError,
      );
    });

    test('无最后移动记录时惩罚仅换人', () {
      final state = buildState(consecutiveSixes: 2);
      final penalized = AeroplaneEngine.applyThirdSixPenalty(state);
      expect(penalized.planes, state.planes);
      expect(penalized.currentPlayer, AeroplaneColor.red);
      expect(penalized.consecutiveSixes, 0);
    });
  });

  group('终局', () {
    AeroplaneGameState nearFinish(Map<AeroplaneColor, List<PlanePosition>> planes) =>
        buildState(planes: planes, currentPlayer: AeroplaneColor.red);

    test('第 4 子恰好抵达即终局', () {
      final state = nearFinish({
        AeroplaneColor.green: allInHangar(),
        AeroplaneColor.red: [
          PlanePosition(zone: PlaneZone.goal, index: 0),
          PlanePosition(zone: PlaneZone.goal, index: 0),
          PlanePosition(zone: PlaneZone.goal, index: 0),
          runwayAt(4),
        ],
        AeroplaneColor.blue: allInHangar(),
        AeroplaneColor.yellow: allInHangar(),
      });
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.red, planeId: 3),
        1,
      );
      expect(moved.gameOver, isTrue);
      expect(moved.winner, AeroplaneColor.red);
      expect(moved.currentPlayer, AeroplaneColor.red);
      expect(
        moved.planesOf(AeroplaneColor.red).every((p) => p.zone == PlaneZone.goal),
        isTrue,
      );
    });

    test('未满 4 子抵达不终局，正常换人', () {
      final state = nearFinish({
        AeroplaneColor.green: allInHangar(),
        AeroplaneColor.red: [
          PlanePosition(zone: PlaneZone.goal, index: 0),
          PlanePosition(zone: PlaneZone.goal, index: 0),
          runwayAt(4),
          allInHangar()[3],
        ],
        AeroplaneColor.blue: allInHangar(),
        AeroplaneColor.yellow: allInHangar(),
      });
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.red, planeId: 2),
        2,
      );
      expect(moved.gameOver, isFalse);
      expect(moved.winner, isNull);
      expect(moved.currentPlayer, AeroplaneColor.blue);
    });

    test('终局后禁走：走法为空且各操作入口抛错', () {
      final state = buildState(
        planes: {
          AeroplaneColor.green: allInHangar(),
          AeroplaneColor.red: [
            for (var i = 0; i < 4; i++)
              PlanePosition(zone: PlaneZone.goal, index: 0),
          ],
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
        currentPlayer: AeroplaneColor.red,
        consecutiveSixes: 2,
        gameOver: true,
        winner: AeroplaneColor.red,
      );
      expect(AeroplaneEngine.isThirdSixPenalty(state, 6), isFalse);
      expect(AeroplaneEngine.legalMoves(state, 6), isEmpty);
      expect(
        () => AeroplaneEngine.applyMove(
          state,
          const AeroplaneMove(color: AeroplaneColor.red, planeId: 0),
          6,
        ),
        throwsArgumentError,
      );
      expect(() => AeroplaneEngine.skipTurn(state), throwsArgumentError);
      expect(
        () => AeroplaneEngine.applyThirdSixPenalty(state),
        throwsArgumentError,
      );
    });
  });

  group('完整对局脚本', () {
    test('多回合序列快照：顺跳再掷、连 6 惩罚、换人轮转', () {
      var state = buildState(
        planes: {
          for (final color in AeroplaneColor.values)
            color: [
              ringAtSteps(color, 0),
              ...allInHangar().skip(1),
            ],
        },
      );
      AeroplaneGameState step(
        AeroplaneMove move,
        int dice,
      ) {
        final next = AeroplaneEngine.applyMove(state, move, dice);
        state = next;
        return next;
      }

      // 1. 绿掷 4 落己色格顺跳（再掷）
      var moved = step(
        const AeroplaneMove(color: AeroplaneColor.green, planeId: 0),
        4,
      );
      expect(moved.planesOf(AeroplaneColor.green)[0], ringAtSteps(AeroplaneColor.green, 8));
      expect(moved.currentPlayer, AeroplaneColor.green);
      expect(moved.consecutiveSixes, 0);

      // 2. 绿掷 6 前进（再掷，计数 1）
      moved = step(
        const AeroplaneMove(color: AeroplaneColor.green, planeId: 0),
        6,
      );
      expect(moved.planesOf(AeroplaneColor.green)[0], ringAtSteps(AeroplaneColor.green, 14));
      expect(moved.currentPlayer, AeroplaneColor.green);
      expect(moved.consecutiveSixes, 1);

      // 3. 绿再掷 6 落己色格顺跳（计数 2）
      moved = step(
        const AeroplaneMove(color: AeroplaneColor.green, planeId: 0),
        6,
      );
      expect(moved.planesOf(AeroplaneColor.green)[0], ringAtSteps(AeroplaneColor.green, 24));
      expect(moved.currentPlayer, AeroplaneColor.green);
      expect(moved.consecutiveSixes, 2);

      // 4. 绿掷第 3 个 6：惩罚，绿0 回停机坪 0 号机位并换红
      expect(AeroplaneEngine.isThirdSixPenalty(state, 6), isTrue);
      state = AeroplaneEngine.applyThirdSixPenalty(state);
      expect(
        state.planesOf(AeroplaneColor.green)[0],
        PlanePosition(zone: PlaneZone.hangar, index: 0),
      );
      expect(state.currentPlayer, AeroplaneColor.red);
      expect(state.consecutiveSixes, 0);

      // 5. 红掷 3 前进无触发，换蓝
      moved = step(
        const AeroplaneMove(color: AeroplaneColor.red, planeId: 0),
        3,
      );
      expect(moved.planesOf(AeroplaneColor.red)[0], ringAtSteps(AeroplaneColor.red, 3));
      expect(moved.currentPlayer, AeroplaneColor.blue);

      // 6. 蓝掷 6 前进（再掷，计数 1）
      moved = step(
        const AeroplaneMove(color: AeroplaneColor.blue, planeId: 0),
        6,
      );
      expect(moved.planesOf(AeroplaneColor.blue)[0], ringAtSteps(AeroplaneColor.blue, 6));
      expect(moved.currentPlayer, AeroplaneColor.blue);
      expect(moved.consecutiveSixes, 1);

      // 7. 蓝掷 1 前进无触发，换黄
      moved = step(
        const AeroplaneMove(color: AeroplaneColor.blue, planeId: 0),
        1,
      );
      expect(moved.planesOf(AeroplaneColor.blue)[0], ringAtSteps(AeroplaneColor.blue, 7));
      expect(moved.currentPlayer, AeroplaneColor.yellow);

      // 8. 黄掷 2 前进换绿，对局持续
      moved = step(
        const AeroplaneMove(color: AeroplaneColor.yellow, planeId: 0),
        2,
      );
      expect(moved.planesOf(AeroplaneColor.yellow)[0], ringAtSteps(AeroplaneColor.yellow, 2));
      expect(moved.currentPlayer, AeroplaneColor.green);
      expect(moved.gameOver, isFalse);
    });

    test('无可动跳过与第 4 子抵达收局', () {
      var state = buildState(
        planes: {
          AeroplaneColor.green: allInHangar(),
          AeroplaneColor.red: [
            PlanePosition(zone: PlaneZone.goal, index: 0),
            PlanePosition(zone: PlaneZone.goal, index: 0),
            PlanePosition(zone: PlaneZone.goal, index: 0),
            runwayAt(4),
          ],
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
        currentPlayer: AeroplaneColor.green,
      );
      expect(AeroplaneEngine.legalMoves(state, 1), isEmpty);
      state = AeroplaneEngine.skipTurn(state);
      expect(state.currentPlayer, AeroplaneColor.red);
      state = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.red, planeId: 3),
        1,
      );
      expect(state.gameOver, isTrue);
      expect(state.winner, AeroplaneColor.red);
      expect(
        state.planesOf(AeroplaneColor.red).every((p) => p.zone == PlaneZone.goal),
        isTrue,
      );
    });
  });

  group('非法输入', () {
    AeroplaneGameState baseState() => buildState(
          planes: {
            AeroplaneColor.green: [
              ringAtSteps(AeroplaneColor.green, 0),
              ...allInHangar().skip(1),
            ],
            AeroplaneColor.red: allInHangar(),
            AeroplaneColor.blue: allInHangar(),
            AeroplaneColor.yellow: allInHangar(),
          },
        );

    test('骰点超出 1..6 抛错', () {
      final state = baseState();
      expect(() => AeroplaneEngine.legalMoves(state, 0), throwsArgumentError);
      expect(() => AeroplaneEngine.legalMoves(state, 7), throwsArgumentError);
      expect(
        () => AeroplaneEngine.applyMove(
          state,
          const AeroplaneMove(color: AeroplaneColor.green, planeId: 0),
          0,
        ),
        throwsArgumentError,
      );
    });

    test('走法颜色与当前行动方不符抛错', () {
      expect(
        () => AeroplaneEngine.applyMove(
          baseState(),
          const AeroplaneMove(color: AeroplaneColor.red, planeId: 0),
          6,
        ),
        throwsArgumentError,
      );
    });

    test('棋子编号越界抛错', () {
      expect(
        () => AeroplaneEngine.applyMove(
          baseState(),
          const AeroplaneMove(color: AeroplaneColor.green, planeId: 4),
          6,
        ),
        throwsArgumentError,
      );
      expect(
        () => AeroplaneEngine.applyMove(
          baseState(),
          const AeroplaneMove(color: AeroplaneColor.green, planeId: -1),
          6,
        ),
        throwsArgumentError,
      );
    });

    test('执行不在合法列表内的走法抛错（停机坪棋子掷 3）', () {
      expect(
        () => AeroplaneEngine.applyMove(
          baseState(),
          const AeroplaneMove(color: AeroplaneColor.green, planeId: 1),
          3,
        ),
        throwsArgumentError,
      );
    });

    test('外环棋子位于不可达格抛错', () {
      // 绿方起飞格 43，格 42 在其入口（39）与起飞格之间的短弧上，绿方棋子不可达
      final state = buildState(
        planes: {
          AeroplaneColor.green: [
            PlanePosition(zone: PlaneZone.ring, index: 42),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.red: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
      );
      expect(() => AeroplaneEngine.legalMoves(state, 6), throwsArgumentError);
    });
  });
}
