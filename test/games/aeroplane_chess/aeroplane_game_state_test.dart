import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';

void main() {
  final savedAt = DateTime(2026, 10, 1, 12);

  List<AeroplanePlayer> fourPlayers() => const [
        AeroplanePlayer(color: AeroplaneColor.green, name: '玩家1'),
        AeroplanePlayer(color: AeroplaneColor.red, name: '玩家2'),
        AeroplanePlayer(color: AeroplaneColor.blue, name: '玩家3'),
        AeroplanePlayer(color: AeroplaneColor.yellow, name: '玩家4'),
      ];

  Map<AeroplaneColor, List<PlanePosition>> allInHangar() => {
        for (final color in AeroplaneColor.values)
          color: [
            for (var i = 0; i < 4; i++)
              PlanePosition(zone: PlaneZone.hangar, index: i),
          ],
      };

  AeroplaneGameState buildState({
    List<AeroplanePlayer>? players,
    Map<AeroplaneColor, List<PlanePosition>>? planes,
    AeroplaneColor currentPlayer = AeroplaneColor.green,
    int consecutiveSixes = 0,
    bool gameOver = false,
    AeroplaneColor? winner,
    (AeroplaneColor, int)? lastMoved,
  }) =>
      AeroplaneGameState(
        players: players ?? fourPlayers(),
        planes: planes ?? allInHangar(),
        currentPlayer: currentPlayer,
        consecutiveSixes: consecutiveSixes,
        gameOver: gameOver,
        winner: winner,
        lastMoved: lastMoved,
        savedAt: savedAt,
      );

  AeroplaneGameState roundTrip(AeroplaneGameState state) =>
      AeroplaneGameState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
      );

  group('PlanePosition', () {
    test('同区域同索引的位置相等', () {
      expect(
        PlanePosition(zone: PlaneZone.ring, index: 7),
        PlanePosition(zone: PlaneZone.ring, index: 7),
      );
      expect(
        PlanePosition(zone: PlaneZone.ring, index: 7) ==
            PlanePosition(zone: PlaneZone.ring, index: 8),
        isFalse,
      );
    });

    test('停机坪索引范围 0..3', () {
      expect(PlanePosition(zone: PlaneZone.hangar, index: 0).index, 0);
      expect(PlanePosition(zone: PlaneZone.hangar, index: 3).index, 3);
      expect(
        () => PlanePosition(zone: PlaneZone.hangar, index: 4),
        throwsArgumentError,
      );
      expect(
        () => PlanePosition(zone: PlaneZone.hangar, index: -1),
        throwsArgumentError,
      );
    });

    test('跑道索引范围 0..4（末格即终点格，归 goal 表达）', () {
      expect(PlanePosition(zone: PlaneZone.runway, index: 0).index, 0);
      expect(PlanePosition(zone: PlaneZone.runway, index: 4).index, 4);
      expect(
        () => PlanePosition(zone: PlaneZone.runway, index: 5),
        throwsArgumentError,
      );
    });

    test('外环索引只要求非负（上界由拓扑表约束）', () {
      expect(PlanePosition(zone: PlaneZone.ring, index: 0).index, 0);
      expect(PlanePosition(zone: PlaneZone.ring, index: 51).index, 51);
      expect(
        () => PlanePosition(zone: PlaneZone.ring, index: -1),
        throwsArgumentError,
      );
    });

    test('准备区索引恒为 0 且编码可解析', () {
      expect(PlanePosition(zone: PlaneZone.ready, index: 0).index, 0);
      expect(
        () => PlanePosition(zone: PlaneZone.ready, index: 1),
        throwsArgumentError,
      );
      expect(PlaneZone.parse('ready'), PlaneZone.ready);
    });

    test('终点索引为基地机位 0..3（完成的飞机飞回基地展示）', () {
      expect(PlanePosition(zone: PlaneZone.goal, index: 0).index, 0);
      expect(PlanePosition(zone: PlaneZone.goal, index: 3).index, 3);
      expect(
        () => PlanePosition(zone: PlaneZone.goal, index: 4),
        throwsArgumentError,
      );
      expect(
        () => PlanePosition(zone: PlaneZone.goal, index: -1),
        throwsArgumentError,
      );
    });
  });

  group('AeroplaneGameState 构造校验', () {
    test('人数少于 2 或多于 4 抛错', () {
      final one = fourPlayers().sublist(0, 1);
      expect(() => buildState(players: one), throwsArgumentError);
      final five = [
        ...fourPlayers(),
        const AeroplanePlayer(color: AeroplaneColor.green, name: '玩家5'),
      ];
      expect(() => buildState(players: five), throwsArgumentError);
    });

    test('玩家颜色重复抛错', () {
      final dup = [
        const AeroplanePlayer(color: AeroplaneColor.green, name: '玩家1'),
        const AeroplanePlayer(color: AeroplaneColor.green, name: '玩家2'),
      ];
      expect(() => buildState(players: dup), throwsArgumentError);
    });

    test('玩家名为空抛错', () {
      final emptyName = [
        const AeroplanePlayer(color: AeroplaneColor.green, name: ''),
        const AeroplanePlayer(color: AeroplaneColor.red, name: '玩家2'),
      ];
      expect(() => buildState(players: emptyName), throwsArgumentError);
    });

    test('棋子缺失或数量不为 4 抛错', () {
      final missing = allInHangar()..remove(AeroplaneColor.blue);
      expect(() => buildState(planes: missing), throwsArgumentError);

      final short = allInHangar()
        ..[AeroplaneColor.red] = [PlanePosition(zone: PlaneZone.hangar, index: 0)];
      expect(() => buildState(planes: short), throwsArgumentError);
    });

    test('当前行动方不是参与玩家抛错', () {
      final twoPlayers = [
        const AeroplanePlayer(color: AeroplaneColor.green, name: '玩家1'),
        const AeroplanePlayer(color: AeroplaneColor.blue, name: '玩家2'),
      ];
      final twoPlanes = {
        AeroplaneColor.green: allInHangar()[AeroplaneColor.green]!,
        AeroplaneColor.blue: allInHangar()[AeroplaneColor.blue]!,
      };
      expect(
        () => buildState(
          players: twoPlayers,
          planes: twoPlanes,
          currentPlayer: AeroplaneColor.red,
        ),
        throwsArgumentError,
      );
    });

    test('连 6 计数为负抛错', () {
      expect(() => buildState(consecutiveSixes: -1), throwsArgumentError);
    });

    test('终局标记与获胜方不一致抛错', () {
      expect(() => buildState(gameOver: true, winner: null), throwsArgumentError);
      expect(
        () => buildState(gameOver: false, winner: AeroplaneColor.red),
        throwsArgumentError,
      );
    });

    test('获胜方不是参与玩家抛错', () {
      final twoPlayers = [
        const AeroplanePlayer(color: AeroplaneColor.green, name: '玩家1'),
        const AeroplanePlayer(color: AeroplaneColor.blue, name: '玩家2'),
      ];
      final twoPlanes = {
        AeroplaneColor.green: allInHangar()[AeroplaneColor.green]!,
        AeroplaneColor.blue: allInHangar()[AeroplaneColor.blue]!,
      };
      expect(
        () => buildState(
          players: twoPlayers,
          planes: twoPlanes,
          gameOver: true,
          winner: AeroplaneColor.red,
        ),
        throwsArgumentError,
      );
    });

    test('最后移动棋子非参与玩家或编号越界抛错', () {
      final twoPlayers = [
        const AeroplanePlayer(color: AeroplaneColor.green, name: '玩家1'),
        const AeroplanePlayer(color: AeroplaneColor.blue, name: '玩家2'),
      ];
      final twoPlanes = {
        AeroplaneColor.green: allInHangar()[AeroplaneColor.green]!,
        AeroplaneColor.blue: allInHangar()[AeroplaneColor.blue]!,
      };
      expect(
        () => buildState(
          players: twoPlayers,
          planes: twoPlanes,
          lastMoved: (AeroplaneColor.red, 0),
        ),
        throwsArgumentError,
      );
      expect(
        () => buildState(lastMoved: (AeroplaneColor.green, 4)),
        throwsArgumentError,
      );
      expect(
        () => buildState(lastMoved: (AeroplaneColor.green, -1)),
        throwsArgumentError,
      );
    });
  });

  group('序列化', () {
    test('进行中对局 JSON 往返一致', () {
      final state = buildState(
        planes: {
          AeroplaneColor.green: [
            PlanePosition(zone: PlaneZone.hangar, index: 0),
            PlanePosition(zone: PlaneZone.ring, index: 5),
            PlanePosition(zone: PlaneZone.runway, index: 2),
            PlanePosition(zone: PlaneZone.goal, index: 0),
          ],
          AeroplaneColor.red: allInHangar()[AeroplaneColor.red]!,
          AeroplaneColor.blue: allInHangar()[AeroplaneColor.blue]!,
          AeroplaneColor.yellow: allInHangar()[AeroplaneColor.yellow]!,
        },
        currentPlayer: AeroplaneColor.red,
        consecutiveSixes: 2,
      );

      final restored = roundTrip(state);

      expect(restored.players, state.players);
      expect(restored.planes, state.planes);
      expect(restored.currentPlayer, AeroplaneColor.red);
      expect(restored.consecutiveSixes, 2);
      expect(restored.gameOver, isFalse);
      expect(restored.winner, isNull);
      expect(restored.savedAt, savedAt);
    });

    test('终局状态往返一致（获胜方保留）', () {
      final state = buildState(
        planes: {
          AeroplaneColor.green: allInHangar()[AeroplaneColor.green]!,
          AeroplaneColor.red: [
            for (var i = 0; i < 4; i++) PlanePosition(zone: PlaneZone.goal, index: 0),
          ],
          AeroplaneColor.blue: allInHangar()[AeroplaneColor.blue]!,
          AeroplaneColor.yellow: allInHangar()[AeroplaneColor.yellow]!,
        },
        gameOver: true,
        winner: AeroplaneColor.red,
      );

      final restored = roundTrip(state);

      expect(restored.gameOver, isTrue);
      expect(restored.winner, AeroplaneColor.red);
      expect(restored.arrivedCount(AeroplaneColor.red), 4);
    });

    test('2 人对局（对角两色）往返一致', () {
      final state = buildState(
        players: [
          const AeroplanePlayer(color: AeroplaneColor.green, name: '玩家1'),
          const AeroplanePlayer(color: AeroplaneColor.blue, name: '玩家2'),
        ],
        planes: {
          AeroplaneColor.green: allInHangar()[AeroplaneColor.green]!,
          AeroplaneColor.blue: allInHangar()[AeroplaneColor.blue]!,
        },
        currentPlayer: AeroplaneColor.blue,
      );

      final restored = roundTrip(state);

      expect(restored.players, hasLength(2));
      expect(restored.planes.keys, {AeroplaneColor.green, AeroplaneColor.blue});
      expect(restored.currentPlayer, AeroplaneColor.blue);
    });

    test('toJson 携带 version 字段且与模型版本一致', () {
      final json = buildState().toJson();
      expect(json['version'], AeroplaneGameState.version);
    });

    test('players 字段缺失或条目非法抛格式异常', () {
      expect(
        () => AeroplaneGameState.fromJson(buildState().toJson()..remove('players')),
        throwsFormatException,
      );

      final badEntry = buildState().toJson();
      badEntry['players'] = [
        ['green'],
      ];
      expect(() => AeroplaneGameState.fromJson(badEntry), throwsFormatException);

      final unknownColor = buildState().toJson();
      unknownColor['players'] = [
        ['purple', '玩家1'],
        ['red', '玩家2'],
      ];
      expect(
        () => AeroplaneGameState.fromJson(unknownColor),
        throwsFormatException,
      );
    });

    test('planes 字段缺失、条目缺失或位置非法抛格式异常', () {
      expect(
        () => AeroplaneGameState.fromJson(buildState().toJson()..remove('planes')),
        throwsFormatException,
      );

      final missingColor = buildState().toJson();
      (missingColor['planes'] as Map<String, dynamic>).remove('blue');
      expect(
        () => AeroplaneGameState.fromJson(missingColor),
        throwsFormatException,
      );

      final badZone = buildState().toJson();
      badZone['planes'] = {
        'green': [
          ['hangar', 0],
          ['hangar', 1],
          ['hangar', 2],
          ['sky', 0],
        ],
        'red': [
          for (var i = 0; i < 4; i++) ['hangar', i],
        ],
        'blue': [
          for (var i = 0; i < 4; i++) ['hangar', i],
        ],
        'yellow': [
          for (var i = 0; i < 4; i++) ['hangar', i],
        ],
      };
      expect(() => AeroplaneGameState.fromJson(badZone), throwsFormatException);

      final outOfRange = buildState().toJson();
      outOfRange['planes'] = {
        'green': [
          ['hangar', 0],
          ['hangar', 1],
          ['hangar', 2],
          ['runway', 6],
        ],
        'red': [
          for (var i = 0; i < 4; i++) ['hangar', i],
        ],
        'blue': [
          for (var i = 0; i < 4; i++) ['hangar', i],
        ],
        'yellow': [
          for (var i = 0; i < 4; i++) ['hangar', i],
        ],
      };
      expect(() => AeroplaneGameState.fromJson(outOfRange), throwsFormatException);
    });

    test('currentPlayer 缺失、非法或非参与玩家抛格式异常', () {
      expect(
        () => AeroplaneGameState.fromJson(
          buildState().toJson()..remove('currentPlayer'),
        ),
        throwsFormatException,
      );

      final badCode = buildState().toJson();
      badCode['currentPlayer'] = 'purple';
      expect(() => AeroplaneGameState.fromJson(badCode), throwsFormatException);

      final notInGame = buildState().toJson();
      notInGame['players'] = [
        ['green', '玩家1'],
        ['blue', '玩家2'],
      ];
      notInGame['planes'] = {
        'green': [
          for (var i = 0; i < 4; i++) ['hangar', i],
        ],
        'blue': [
          for (var i = 0; i < 4; i++) ['hangar', i],
        ],
      };
      notInGame['currentPlayer'] = 'red';
      expect(() => AeroplaneGameState.fromJson(notInGame), throwsFormatException);
    });

    test('consecutiveSixes 缺失或为负抛格式异常', () {
      expect(
        () => AeroplaneGameState.fromJson(
          buildState().toJson()..remove('consecutiveSixes'),
        ),
        throwsFormatException,
      );

      final negative = buildState().toJson();
      negative['consecutiveSixes'] = -1;
      expect(() => AeroplaneGameState.fromJson(negative), throwsFormatException);
    });

    test('gameOver 缺失或与 winner 冲突抛格式异常', () {
      expect(
        () => AeroplaneGameState.fromJson(buildState().toJson()..remove('gameOver')),
        throwsFormatException,
      );

      final winnerWithoutOver = buildState().toJson();
      winnerWithoutOver['winner'] = 'red';
      expect(
        () => AeroplaneGameState.fromJson(winnerWithoutOver),
        throwsFormatException,
      );

      final overWithoutWinner = buildState(gameOver: true, winner: AeroplaneColor.red)
          .toJson();
      overWithoutWinner.remove('winner');
      expect(
        () => AeroplaneGameState.fromJson(overWithoutWinner),
        throwsFormatException,
      );
    });

    test('savedAt 无效时间字符串抛格式异常', () {
      final badTime = buildState().toJson();
      badTime['savedAt'] = 'not-a-date';
      expect(() => AeroplaneGameState.fromJson(badTime), throwsFormatException);
    });

    test('lastMoved 往返一致（含空值）', () {
      final withLast = roundTrip(
        buildState(lastMoved: (AeroplaneColor.green, 2)),
      );
      expect(withLast.lastMoved, (AeroplaneColor.green, 2));
      expect(roundTrip(buildState()).lastMoved, isNull);
    });

    test('lastMoved 字段非法抛格式异常', () {
      final badShape = buildState().toJson();
      badShape['lastMoved'] = ['green'];
      expect(() => AeroplaneGameState.fromJson(badShape), throwsFormatException);

      final badColor = buildState().toJson();
      badColor['lastMoved'] = ['purple', 0];
      expect(() => AeroplaneGameState.fromJson(badColor), throwsFormatException);

      final outOfRange = buildState().toJson();
      outOfRange['lastMoved'] = ['green', 9];
      expect(
        () => AeroplaneGameState.fromJson(outOfRange),
        throwsFormatException,
      );
    });
  });

  group('summary 摘要', () {
    test('进行中对局：进度领先者 + 当前行动方', () {
      final state = buildState(
        planes: {
          AeroplaneColor.green: allInHangar()[AeroplaneColor.green]!,
          AeroplaneColor.red: [
            PlanePosition(zone: PlaneZone.goal, index: 0),
            PlanePosition(zone: PlaneZone.goal, index: 0),
            PlanePosition(zone: PlaneZone.ring, index: 10),
            PlanePosition(zone: PlaneZone.hangar, index: 3),
          ],
          AeroplaneColor.blue: allInHangar()[AeroplaneColor.blue]!,
          AeroplaneColor.yellow: allInHangar()[AeroplaneColor.yellow]!,
        },
        currentPlayer: AeroplaneColor.blue,
      );
      expect(state.summary, '红 2/4 到达，轮到蓝方');
    });

    test('开局状态：首位玩家 0/4', () {
      expect(buildState().summary, '绿 0/4 到达，轮到绿方');
    });

    test('终局状态：展示获胜方', () {
      final state = buildState(gameOver: true, winner: AeroplaneColor.red);
      expect(state.summary, '红方胜利');
    });

    test('进度并列取轮转靠前者', () {
      final state = buildState(
        planes: {
          AeroplaneColor.green: [
            PlanePosition(zone: PlaneZone.goal, index: 0),
            PlanePosition(zone: PlaneZone.hangar, index: 1),
            PlanePosition(zone: PlaneZone.hangar, index: 2),
            PlanePosition(zone: PlaneZone.hangar, index: 3),
          ],
          AeroplaneColor.red: [
            PlanePosition(zone: PlaneZone.goal, index: 0),
            PlanePosition(zone: PlaneZone.hangar, index: 1),
            PlanePosition(zone: PlaneZone.hangar, index: 2),
            PlanePosition(zone: PlaneZone.hangar, index: 3),
          ],
          AeroplaneColor.blue: allInHangar()[AeroplaneColor.blue]!,
          AeroplaneColor.yellow: allInHangar()[AeroplaneColor.yellow]!,
        },
        currentPlayer: AeroplaneColor.yellow,
      );
      expect(state.summary, '绿 1/4 到达，轮到黄方');
    });
  });

  group('开局构建', () {
    test('默认颜色分配：2 人对角、3 人连续、4 人全色', () {
      expect(
        AeroplaneGameState.defaultColors[2],
        [AeroplaneColor.green, AeroplaneColor.blue],
      );
      expect(
        AeroplaneGameState.defaultColors[3],
        [AeroplaneColor.green, AeroplaneColor.red, AeroplaneColor.blue],
      );
      expect(AeroplaneGameState.defaultColors[4], AeroplaneColor.values);
    });

    test('initial：全部棋子在停机坪、首位先手、无连 6 与终局', () {
      final players = [
        for (var i = 0; i < 2; i++)
          AeroplanePlayer(
            color: AeroplaneGameState.defaultColors[2]![i],
            name: '玩家${i + 1}',
          ),
      ];
      final state = AeroplaneGameState.initial(players);
      expect(state.players, players);
      expect(state.currentPlayer, AeroplaneColor.green);
      expect(state.consecutiveSixes, 0);
      expect(state.gameOver, isFalse);
      expect(state.winner, isNull);
      expect(state.lastMoved, isNull);
      for (final color in AeroplaneGameState.defaultColors[2]!) {
        expect(state.planesOf(color), [
          for (var i = 0; i < 4; i++)
            PlanePosition(zone: PlaneZone.hangar, index: i),
        ]);
      }
    });
  });
}
