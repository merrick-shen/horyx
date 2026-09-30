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
  }) {
    final colors = players.map((p) => p.color).toSet();
    return AeroplaneGameState(
      players: players,
      planes: planes ??
          {for (final c in colors) c: allInHangar()},
      currentPlayer: currentPlayer,
      consecutiveSixes: consecutiveSixes,
      gameOver: false,
      winner: null,
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

    test('起飞迁移：落到起飞格，其余棋子不变，换人并清零连 6', () {
      final state = buildState(currentPlayer: AeroplaneColor.green);
      final moved = AeroplaneEngine.applyMove(
        state,
        const AeroplaneMove(color: AeroplaneColor.green, planeId: 2),
        6,
      );
      expect(
        moved.planesOf(AeroplaneColor.green)[2],
        PlanePosition(
          zone: PlaneZone.ring,
          index: AeroplaneBoard.takeoffIndex[AeroplaneColor.green]!,
        ),
      );
      expect(moved.planesOf(AeroplaneColor.green)[0].zone, PlaneZone.hangar);
      expect(moved.currentPlayer, AeroplaneColor.red);
      expect(moved.consecutiveSixes, 0);
      expect(moved.savedAt, savedAt);
    });
  });

  group('外环前进', () {
    test('按骰点前进，落点与格色无关（当前不含跳跃）', () {
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

    test('落在己色格不跳跃（跳跃尚未接入）', () {
      // 红 4 + 4 = 8，8 为红色格，仍停留原步数对应格
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
        4,
      );
      expect(moved.planesOf(AeroplaneColor.red)[0], ringAtSteps(AeroplaneColor.red, 4));
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
      // 跑道 4 号格 = 行进 53 步，+2 恰好 55 步到终点；跑道 5 +1 同理
      final cases = [(4, 2), (5, 1)];
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

    test('超出终点的步数当前不合法（回退尚未接入）', () {
      final state = buildState(
        planes: {
          AeroplaneColor.red: [
            runwayAt(4),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.green: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
        currentPlayer: AeroplaneColor.red,
      );
      expect(AeroplaneEngine.legalMoves(state, 3), isEmpty);
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

    test('唯一可动棋子超步、其余不可起飞时同样跳过', () {
      final state = buildState(
        planes: {
          AeroplaneColor.red: [
            runwayAt(4),
            ...allInHangar().skip(1),
          ],
          AeroplaneColor.green: allInHangar(),
          AeroplaneColor.blue: allInHangar(),
          AeroplaneColor.yellow: allInHangar(),
        },
        currentPlayer: AeroplaneColor.red,
      );
      expect(AeroplaneEngine.legalMoves(state, 5), isEmpty);
      final skipped = AeroplaneEngine.skipTurn(state);
      expect(skipped.currentPlayer, AeroplaneColor.blue);
    });

    test('已抵达终点的棋子不再产生走法', () {
      final state = buildState(
        planes: {
          AeroplaneColor.red: [
            PlanePosition(zone: PlaneZone.goal, index: 0),
            runwayAt(5),
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
