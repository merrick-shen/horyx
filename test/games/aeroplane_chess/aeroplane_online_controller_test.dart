import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';
import 'package:horyx/games/aeroplane_chess/services/aeroplane_net_models.dart';
import 'package:horyx/games/aeroplane_chess/services/aeroplane_online_controller.dart';
import 'package:horyx/shared/network/net_message.dart';
import 'package:horyx/shared/network/online_game_controller.dart';
import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/network/room_host.dart';

/// 飞行棋联机控制器测试：消息编解码 + 本机回环真实 TCP 集成
/// 覆盖：编解码往返与损坏容错、开局快照同步、掷骰/跳过/三 6 惩罚流转、
/// 走子校验拒绝回执、seq 幂等（重复/乱序）、非法消息容错、
/// 中途退出与房主解散的终局传播
void main() {
  // 轮询等待异步事件（网络消息到达无回调可 await，只能按状态轮询）
  Future<void> until(
    bool Function() test, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (test()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('等待条件超时');
  }

  group('消息编解码', () {
    test('掷骰结果往返一致', () {
      final decoded = AeroplaneNetRoll.fromMessage(
        AeroplaneNetRoll(value: 6, seq: 3).toMessage(),
      );
      expect(decoded, isNotNull);
      expect(decoded!.value, 6);
      expect(decoded.seq, 3);
    });

    test('掷骰结果：载荷损坏返回 null', () {
      expect(
        AeroplaneNetRoll.fromMessage(
          const NetMessage(type: NetMessageType.aeroplaneRollResult),
        ),
        isNull,
        reason: '字段缺失',
      );
      expect(
        AeroplaneNetRoll.fromMessage(
          const NetMessage(
            type: NetMessageType.aeroplaneRollResult,
            payload: {'value': 9, 'seq': 1},
          ),
        ),
        isNull,
        reason: '骰点越界',
      );
      expect(
        AeroplaneNetRoll.fromMessage(
          const NetMessage(
            type: NetMessageType.aeroplaneRollResult,
            payload: {'value': '6', 'seq': 1},
          ),
        ),
        isNull,
        reason: '类型不符',
      );
      expect(
        AeroplaneNetRoll.fromMessage(
          const NetMessage(
            type: NetMessageType.aeroplaneRollResult,
            payload: {'value': 3, 'seq': 0},
          ),
        ),
        isNull,
        reason: '序号非正',
      );
    });

    test('走子提交往返一致（fly 缺省按不飞越）', () {
      final decoded = parseAeroplaneMoveSubmit(
        aeroplaneMoveSubmitMessage(planeId: 2, fly: true),
      );
      expect(decoded?.planeId, 2);
      expect(decoded?.fly, isTrue);
      expect(
        parseAeroplaneMoveSubmit(
          const NetMessage(
            type: NetMessageType.aeroplaneMoveSubmit,
            payload: {'planeId': 0},
          ),
        )?.fly,
        isFalse,
      );
    });

    test('走子提交：编号越界/类型不符/缺失返回 null', () {
      final payloads = <Map<String, dynamic>>[
        {},
        {'planeId': -1},
        {'planeId': 4},
        {'planeId': '0'},
      ];
      for (final payload in payloads) {
        expect(
          parseAeroplaneMoveSubmit(
            NetMessage(type: NetMessageType.aeroplaneMoveSubmit, payload: payload),
          ),
          isNull,
          reason: '$payload',
        );
      }
    });

    test('状态快照往返一致', () {
      final state = AeroplaneGameState.initial(const [
        AeroplanePlayer(color: AeroplaneColor.green, name: '甲'),
        AeroplanePlayer(color: AeroplaneColor.blue, name: '乙'),
      ]);
      final decoded = parseAeroplaneState(
        aeroplaneStateMessage(seq: 7, state: state),
      );
      expect(decoded?.seq, 7);
      expect(decoded?.state.toJson(), state.toJson());
    });

    test('状态快照：载荷损坏返回 null', () {
      expect(
        parseAeroplaneState(
          const NetMessage(type: NetMessageType.aeroplaneState),
        ),
        isNull,
        reason: '字段缺失',
      );
      expect(
        parseAeroplaneState(
          const NetMessage(
            type: NetMessageType.aeroplaneState,
            payload: {'seq': 0},
          ),
        ),
        isNull,
        reason: '序号非正',
      );
      expect(
        parseAeroplaneState(
          NetMessage(
            type: NetMessageType.aeroplaneState,
            payload: {
              'seq': 1,
              'state': {'junk': true},
            },
          ),
        ),
        isNull,
        reason: '状态损坏',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 集成测试：本机回环真实 TCP（与 word_pk/tank 联机测试同模式）
  // ---------------------------------------------------------------------------

  /// 建满员房间并接管全端控制器（控制器销毁由 tearDown 统一负责）
  Future<
    (
      RoomHost,
      List<RoomClient>,
      AeroplaneOnlineController,
      List<AeroplaneOnlineController>,
    )
  >
  setUpRoom({required int capacity, List<int>? diceScript}) async {
    final host = RoomHost(
      gameName: '飞行棋',
      hostName: '房主',
      capacity: capacity,
      basePort: 0,
    );
    expect(await host.start(), isTrue);
    final clients = [
      for (var i = 0; i < capacity - 1; i++)
        RoomClient(host: '127.0.0.1', port: host.port, myName: '客户端${i + 1}'),
    ];
    for (final client in clients) {
      unawaited(client.connect());
    }
    await until(() => clients.every((c) => c.phase == RoomClientPhase.gameStarting));
    final hostCtrl = AeroplaneOnlineController.host(
      host,
      random: diceScript == null ? null : _ScriptedRandom(diceScript),
    );
    final clientCtrls = [
      for (final client in clients) AeroplaneOnlineController.client(client),
    ];
    addTearDown(hostCtrl.dispose);
    for (final ctrl in clientCtrls) {
      addTearDown(ctrl.dispose);
    }
    return (host, clients, hostCtrl, clientCtrls);
  }

  test('满员开局：全端同步初始快照（颜色分配/座位映射/先手）', () async {
    final (_, _, hostCtrl, clientCtrls) = await setUpRoom(capacity: 4);
    await until(() => clientCtrls.every((c) => c.state != null));

    // 房主权威全量快照：各端状态与房主逐字段一致
    for (final ctrl in clientCtrls) {
      expect(ctrl.state!.toJson(), hostCtrl.state!.toJson());
    }
    final state = hostCtrl.state!;
    expect(state.players.map((p) => p.color).toList(), AeroplaneColor.values);
    expect(
      state.players.map((p) => p.name).toList(),
      ['房主', '客户端1', '客户端2', '客户端3'],
    );
    expect(state.currentPlayer, AeroplaneColor.green);
    // 座位 → 颜色：房主 1 号绿，客户端按入座序 红/蓝/黄
    expect(hostCtrl.myColor, AeroplaneColor.green);
    expect(clientCtrls[0].myColor, AeroplaneColor.red);
    expect(clientCtrls[1].myColor, AeroplaneColor.blue);
    expect(clientCtrls[2].myColor, AeroplaneColor.yellow);
    expect(hostCtrl.isMyTurn, isTrue);
    expect(clientCtrls.every((c) => !c.isMyTurn), isTrue);
    expect(hostCtrl.winnerSeat, isNull);
  });

  test('客户端晚挂接：暂存的开局快照回放不丢', () async {
    final host = RoomHost(
      gameName: '飞行棋',
      hostName: '房主',
      capacity: 2,
      basePort: 0,
    );
    expect(await host.start(), isTrue);
    final client = RoomClient(host: '127.0.0.1', port: host.port, myName: '客户端1');
    unawaited(client.connect());
    await until(() => client.phase == RoomClientPhase.gameStarting);

    final hostCtrl = AeroplaneOnlineController.host(host);
    // 让开局快照先到达（控制器挂接前的间隙由 RoomClient 暂存）
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final clientCtrl = AeroplaneOnlineController.client(client);
    expect(clientCtrl.state, isNotNull);
    expect(clientCtrl.state!.toJson(), hostCtrl.state!.toJson());
    expect(clientCtrl.myColor, AeroplaneColor.blue);

    hostCtrl.dispose();
    clientCtrl.dispose();
  });

  test('掷骰与回合流转：无可动自动跳过，起飞走子全端同步', () async {
    final (_, clients, hostCtrl, clientCtrls) = await setUpRoom(
      capacity: 2,
      diceScript: [1, 2],
    );
    final clientCtrl = clientCtrls[0];
    await until(() => clientCtrl.state != null);

    // 房主掷 1：全子在停机坪、1 非起飞点数 → 自动跳过换人
    expect(hostCtrl.rollDice(), isTrue);
    await until(() => clientCtrl.state!.currentPlayer == AeroplaneColor.blue);
    expect(hostCtrl.state!.currentPlayer, AeroplaneColor.blue);
    expect(hostCtrl.pendingDice, isNull);
    expect(clientCtrl.pendingDice, isNull);

    // 客户端掷 2（骰子仍由房主生成）；重复请求只生效一次
    expect(clientCtrl.rollDice(), isTrue);
    clients[0].send(aeroplaneRollRequestMessage());
    await until(() => clientCtrl.pendingDice == 2);
    expect(hostCtrl.pendingDice, 2);
    expect(clientCtrl.isMyTurn, isTrue);

    // 客户端起飞：棋子进准备区；2 非 6 无奖励，回合回到房主
    // （等待条件观察客户端：其状态经网络到达，避免房主侧同步状态不等待）
    expect(clientCtrl.submitMove(0), isTrue);
    await until(() => clientCtrl.state!.currentPlayer == AeroplaneColor.green);
    expect(clientCtrl.state!.toJson(), hostCtrl.state!.toJson());
    expect(
      clientCtrl.state!.planesOf(AeroplaneColor.blue)[0].zone,
      PlaneZone.ready,
    );
    expect(clientCtrl.pendingDice, isNull);
  });

  test('连掷三个 6：惩罚自动生效，最后移动的棋子返回停机坪', () async {
    final (_, _, hostCtrl, clientCtrls) = await setUpRoom(
      capacity: 2,
      diceScript: [6],
    );
    final clientCtrl = clientCtrls[0];
    await until(() => clientCtrl.state != null);

    // 第 1 个 6：起飞进准备区（掷 6 奖励再掷）
    expect(hostCtrl.rollDice(), isTrue);
    await until(() => hostCtrl.pendingDice == 6);
    expect(hostCtrl.submitMove(0), isTrue);
    await until(
      () =>
          hostCtrl.state!.consecutiveSixes == 1 && hostCtrl.pendingDice == null,
    );
    expect(hostCtrl.state!.currentPlayer, AeroplaneColor.green);

    // 第 2 个 6：准备区棋子行进（仍奖励再掷）
    expect(hostCtrl.rollDice(), isTrue);
    await until(() => hostCtrl.pendingDice == 6);
    expect(hostCtrl.submitMove(0), isTrue);
    await until(
      () =>
          hostCtrl.state!.consecutiveSixes == 2 && hostCtrl.pendingDice == null,
    );

    // 第 3 个 6：惩罚直接生效（无需走子提交），棋子回停机坪并换人。
    // 等待条件观察客户端：房主侧迁移全部同步完成，若只等房主状态则
    // 事件循环未让出，客户端广播尚未送达即断言
    expect(hostCtrl.rollDice(), isTrue);
    await until(() => clientCtrl.state!.currentPlayer == AeroplaneColor.blue);
    expect(
      hostCtrl.state!.planesOf(AeroplaneColor.green)[0].zone,
      PlaneZone.hangar,
    );
    expect(hostCtrl.state!.consecutiveSixes, 0);
    expect(hostCtrl.pendingDice, isNull);
    // 客户端收到惩罚后的全量快照，与房主一致
    expect(clientCtrl.state!.toJson(), hostCtrl.state!.toJson());
  });

  test('走子校验：轮次/骰点/合法性逐层拒绝并回执', () async {
    final (_, clients, hostCtrl, clientCtrls) = await setUpRoom(
      capacity: 2,
      diceScript: [1, 2],
    );
    final clientCtrl = clientCtrls[0];
    await until(() => clientCtrl.state != null);
    final hints = <String>[];
    clientCtrl.onHint = hints.add;

    // 房主回合客户端提交走子：房主以轮次不符拒绝
    clients[0].send(aeroplaneMoveSubmitMessage(planeId: 0, fly: false));
    await until(() => hints.isNotEmpty);
    expect(hints.last, '还没轮到你走子');

    // 客户端本地预检同源拦截（不发网络）
    hints.clear();
    expect(clientCtrl.submitMove(0), isFalse);
    expect(hints.last, '还没轮到你走子');

    // 房主掷 1 自动跳过，轮到客户端；未掷骰直接提交：缺骰点拒绝
    expect(hostCtrl.rollDice(), isTrue);
    await until(() => clientCtrl.state!.currentPlayer == AeroplaneColor.blue);
    hints.clear();
    clients[0].send(aeroplaneMoveSubmitMessage(planeId: 0, fly: false));
    await until(() => hints.isNotEmpty);
    expect(hints.last, '请先掷骰子再走子');

    // 客户端掷 2 后提交非法走法变体（起飞无飞越变体）：非法走法拒绝
    expect(clientCtrl.rollDice(), isTrue);
    await until(() => clientCtrl.pendingDice == 2);
    hints.clear();
    clients[0].send(aeroplaneMoveSubmitMessage(planeId: 0, fly: true));
    await until(() => hints.isNotEmpty);
    expect(hints.last, '这不是合法走法');
    // 拒绝不改变状态（未迁移）
    expect(clientCtrl.state!.toJson(), hostCtrl.state!.toJson());
    expect(hostCtrl.pendingDice, 2);
  });

  test('非轮次掷骰请求：房主静默忽略', () async {
    final (_, clients, hostCtrl, clientCtrls) = await setUpRoom(capacity: 2);
    final clientCtrl = clientCtrls[0];
    await until(() => clientCtrl.state != null);

    // 房主（绿方）回合，客户端发掷骰请求：不产生骰点
    clients[0].send(aeroplaneRollRequestMessage());
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(hostCtrl.pendingDice, isNull);
    expect(clientCtrl.pendingDice, isNull);
  });

  test('快照按 seq 幂等：陈旧/重复丢弃，乱序取新', () async {
    final (host, _, hostCtrl, clientCtrls) = await setUpRoom(
      capacity: 2,
      diceScript: [2],
    );
    final clientCtrl = clientCtrls[0];
    await until(() => clientCtrl.state != null);
    final initialState = hostCtrl.state!;

    // 房主起飞推进对局（客户端序号已越过开局快照）；
    // 等待条件观察客户端，确保真实快照已送达，再验证旧序号快照被丢弃
    expect(hostCtrl.rollDice(), isTrue);
    await until(() => hostCtrl.pendingDice == 2);
    expect(hostCtrl.submitMove(0), isTrue);
    await until(() => clientCtrl.state!.currentPlayer == AeroplaneColor.blue);
    final currentJson = hostCtrl.state!.toJson();

    // 重发开局快照（旧序号）：客户端状态不变
    host.sendTo(2, aeroplaneStateMessage(seq: 1, state: initialState));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(clientCtrl.state!.toJson(), currentJson);

    // 重发旧序号骰点：不覆盖已消费状态
    host.sendTo(2, AeroplaneNetRoll(value: 5, seq: 1).toMessage());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(clientCtrl.pendingDice, isNull);

    // 乱序：新序号快照先生效，随后的旧序号真实状态被丢弃
    final future = AeroplaneGameState.initial(const [
      AeroplanePlayer(color: AeroplaneColor.green, name: '甲'),
      AeroplanePlayer(color: AeroplaneColor.blue, name: '乙'),
    ]);
    host.sendTo(2, aeroplaneStateMessage(seq: 999, state: future));
    await until(() => clientCtrl.state!.players.first.name == '甲');
    host.sendTo(2, aeroplaneStateMessage(seq: 998, state: hostCtrl.state!));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(clientCtrl.state!.players.first.name, '甲');
  });

  test('非法消息容错：损坏载荷不崩不改状态', () async {
    final (host, clients, hostCtrl, clientCtrls) = await setUpRoom(capacity: 2);
    final clientCtrl = clientCtrls[0];
    await until(() => clientCtrl.state != null);
    final before = clientCtrl.state!.toJson();

    // 客户端 → 房主：非法走子提交与带杂质的掷骰请求
    clients[0].send(
      const NetMessage(
        type: NetMessageType.aeroplaneMoveSubmit,
        payload: {'planeId': 9},
      ),
    );
    clients[0].send(
      const NetMessage(
        type: NetMessageType.aeroplaneMoveSubmit,
        payload: {'planeId': 'x'},
      ),
    );
    clients[0].send(const NetMessage(type: NetMessageType.aeroplaneMoveSubmit));
    clients[0].send(
      const NetMessage(
        type: NetMessageType.aeroplaneRollRequest,
        payload: {'junk': 1},
      ),
    );

    // 房主 → 客户端：损坏的掷骰结果与快照
    host.sendTo(
      2,
      const NetMessage(
        type: NetMessageType.aeroplaneRollResult,
        payload: {'value': 99, 'seq': 8},
      ),
    );
    host.sendTo(
      2,
      const NetMessage(
        type: NetMessageType.aeroplaneRollResult,
        payload: {'value': 3},
      ),
    );
    host.sendTo(
      2,
      const NetMessage(type: NetMessageType.aeroplaneState, payload: {'seq': 8}),
    );
    host.sendTo(
      2,
      NetMessage(
        type: NetMessageType.aeroplaneState,
        payload: {
          'seq': 8,
          'state': {'junk': true},
        },
      ),
    );
    host.sendTo(
      2,
      const NetMessage(
        type: NetMessageType.aeroplaneState,
        payload: {'seq': '8', 'state': {}},
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(clientCtrl.state!.toJson(), before);
    expect(clientCtrl.pendingDice, isNull);
    expect(hostCtrl.state!.toJson(), before);
    expect(hostCtrl.gameEndedText, isNull);
    expect(clientCtrl.gameEndedText, isNull);
  });

  test('终局快照同步：获胜状态生效且禁止继续行动', () async {
    final (host, _, hostCtrl, clientCtrls) = await setUpRoom(capacity: 2);
    final clientCtrl = clientCtrls[0];
    await until(() => clientCtrl.state != null);

    // 构造绿方 4 子全部抵达终点的终局状态，以新序号快照下发
    final players = hostCtrl.state!.players;
    final finished = AeroplaneGameState(
      players: players,
      planes: {
        for (final p in players)
          p.color: [
            for (var i = 0; i < 4; i++)
              p.color == AeroplaneColor.green
                  ? PlanePosition(zone: PlaneZone.goal, index: i)
                  : PlanePosition(zone: PlaneZone.hangar, index: i),
          ],
      },
      currentPlayer: AeroplaneColor.green,
      consecutiveSixes: 0,
      gameOver: true,
      winner: AeroplaneColor.green,
      savedAt: DateTime(2026),
    );
    host.sendTo(2, aeroplaneStateMessage(seq: 999, state: finished));
    await until(() => clientCtrl.state!.gameOver);
    expect(clientCtrl.winnerSeat, 1);
    expect(clientCtrl.isMyTurn, isFalse);
    expect(clientCtrl.rollDice(), isFalse);
    expect(clientCtrl.submitMove(0), isFalse);
  });

  test('中途退出：任一玩家离开即终局，其余玩家收到终局广播', () async {
    final (_, clients, hostCtrl, clientCtrls) = await setUpRoom(capacity: 3);
    await until(() => clientCtrls.every((c) => c.state != null));

    // 座位 2 退出：房主判终局并广播，座位 3 收到终局
    await clients[0].close();
    await until(() => hostCtrl.gameEndedText != null);
    expect(hostCtrl.gameEndReason, EndGameReason.peerLeft);
    await until(() => clientCtrls[1].gameEndedText != null);
    expect(clientCtrls[1].gameEndedText, '其他玩家均已离开，对局结束');
    expect(clientCtrls[1].gameEndReason, EndGameReason.peerLeft);
  });

  test('全员离开：2 人局对方退出房主即终局', () async {
    final (_, clients, hostCtrl, clientCtrls) = await setUpRoom(capacity: 2);
    await until(() => clientCtrls[0].state != null);

    await clients[0].close();
    await until(() => hostCtrl.gameEndedText != null);
    expect(hostCtrl.gameEndedText, '其他玩家均已离开，对局结束');
  });

  test('房主解散：客户端对局终止并提示', () async {
    final (host, _, hostCtrl, clientCtrls) = await setUpRoom(capacity: 2);
    await until(() => clientCtrls[0].state != null);

    await host.close();
    await until(() => clientCtrls[0].gameEndedText != null);
    expect(clientCtrls[0].gameEndedText, '房主已解散房间');
    expect(hostCtrl.gameEndedText, isNull, reason: '房主自行解散不触发其终局信号');
  });
}

/// 脚本随机源：nextInt 按序返回预设骰点（耗尽后循环），
/// 注入房主控制器使掷骰序列确定化
class _ScriptedRandom implements Random {
  _ScriptedRandom(this.script);

  final List<int> script;
  int _index = 0;

  @override
  int nextInt(int max) {
    final value = script[_index % script.length];
    _index++;
    return value - 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
