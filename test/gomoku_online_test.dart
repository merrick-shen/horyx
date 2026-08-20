import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/models/net_message.dart';
import 'package:horyx/services/gomoku/gomoku_online_controller.dart';
import 'package:horyx/services/network/room_client.dart';
import 'package:horyx/services/network/room_host.dart';

/// 五子棋联机对局集成测试：本机回环真实 TCP 连接
/// 覆盖：开局规格同步、轮流落子全端一致、非本人回合/占用拒绝、
/// 五连终局判定、对方离开对局结束（不判胜负）、房主解散终局、
/// 悔棋协商（同意/拒绝）、认输终局
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

  // 收集控制器提示的辅助（校验拒绝等原因）
  List<String> hintsOf(GomokuOnlineController controller) {
    final hints = <String>[];
    controller.onHint = hints.add;
    return hints;
  }

  // 建房 + 加入 + 双端挂控制器的通用前置（各用例仅一步之遥）
  Future<(GomokuOnlineController, GomokuOnlineController)> setupGame(
    Map<String, dynamic> startPayload,
  ) async {
    final host = RoomHost(
      gameName: '五子棋',
      capacity: 2,
      basePort: 0,
      enableDiscovery: false,
      gameStartPayload: startPayload,
    );
    expect(await host.start(), isTrue);
    final client = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(client.connect());
    await until(() => client.phase == RoomClientPhase.gameStarting);
    return (
      GomokuOnlineController.host(host, boardSize: startPayload['boardSize']),
      GomokuOnlineController.client(client),
    );
  }

  test('开局规格同步与轮流落子：双端棋盘一致、回合轮换正确', () async {
    final host = RoomHost(
      gameName: '五子棋',
      capacity: 2,
      basePort: 0,
      enableDiscovery: false,
      gameStartPayload: {'boardSize': 19},
    );
    expect(await host.start(), isTrue);

    final client = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(client.connect());
    await until(() => client.phase == RoomClientPhase.gameStarting);

    // 开局后各端挂接对局控制器（模拟等待页跳转对局页的时序）
    final hostCtrl = GomokuOnlineController.host(host, boardSize: 19);
    final clientCtrl = GomokuOnlineController.client(client);

    // 客户端从开局载荷读到房主所选规格
    expect(clientCtrl.boardSize, 19);
    expect(clientCtrl.isBlack, isFalse); // 客户端座位 2 执白
    expect(hostCtrl.isMyTurn, isTrue); // 黑先，房主先行

    // 房主落子：双端同步，轮到客户端
    expect(hostCtrl.submitStone(7, 7), isTrue);
    await until(() => clientCtrl.moves.length == 1);
    expect(clientCtrl.moves.first, (7, 7));
    expect(clientCtrl.isMyTurn, isTrue);
    expect(hostCtrl.isMyTurn, isFalse);

    // 客户端落子：双端同步，轮回房主
    expect(clientCtrl.submitStone(8, 8), isTrue);
    await until(() => hostCtrl.moves.length == 2);
    expect(hostCtrl.moves.last, (8, 8));
    expect(hostCtrl.isMyTurn, isTrue);
    expect(clientCtrl.isMyTurn, isFalse);

    hostCtrl.dispose();
    clientCtrl.dispose();
  });

  test('非法提交被拒：非本人回合与落点占用', () async {
    final host = RoomHost(
      gameName: '五子棋',
      capacity: 2,
      basePort: 0,
      enableDiscovery: false,
    );
    expect(await host.start(), isTrue);

    final client = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(client.connect());
    await until(() => client.phase == RoomClientPhase.gameStarting);

    final hostCtrl = GomokuOnlineController.host(host, boardSize: 15);
    final clientCtrl = GomokuOnlineController.client(client);
    final hints = hintsOf(clientCtrl);

    // 黑先：客户端（白）此刻提交被本地拦截，不发网络消息
    expect(clientCtrl.submitStone(7, 7), isFalse);
    expect(hints, contains('还没轮到你落子'));

    // 房主先落一子后轮到客户端
    expect(hostCtrl.submitStone(7, 7), isTrue);
    await until(() => clientCtrl.moves.length == 1);

    // 客户端提交占用落点：本地拦截
    hints.clear();
    expect(clientCtrl.submitStone(7, 7), isFalse);
    expect(hints, contains('此处已有棋子'));
    // 合法提交占住 (8,8)
    expect(clientCtrl.submitStone(8, 8), isTrue);
    await until(() => hostCtrl.moves.length == 2);

    // 轮到房主：客户端再提交（此刻已非其回合）被本地拦截
    hints.clear();
    expect(clientCtrl.submitStone(6, 6), isFalse);

    hostCtrl.dispose();
    clientCtrl.dispose();
  });

  test('房主侧终极校验：绕过本地拦截的非法提交被回执拒绝', () async {
    final host = RoomHost(
      gameName: '五子棋',
      capacity: 2,
      basePort: 0,
      enableDiscovery: false,
    );
    expect(await host.start(), isTrue);

    final client = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(client.connect());
    await until(() => client.phase == RoomClientPhase.gameStarting);

    final hostCtrl = GomokuOnlineController.host(host, boardSize: 15);
    final clientCtrl = GomokuOnlineController.client(client);
    final hints = hintsOf(clientCtrl);

    // 直接走网络层发 stoneSubmit（模拟恶意/异版客户端绕过本地拦截）：
    // 白方（座位2）在黑方回合提交 -> 房主回执 notYourTurn
    client.send(const NetMessage(
      type: NetMessageType.stoneSubmit,
      payload: {'col': 7, 'row': 7},
    ));
    await until(() => hints.isNotEmpty);
    expect(hints.last, '还没轮到你落子');
    expect(hostCtrl.moves, isEmpty); // 棋盘未被污染

    hostCtrl.dispose();
    clientCtrl.dispose();
  });

  test('五连终局：黑方五连后双端判定胜负并停止落子', () async {
    final host = RoomHost(
      gameName: '五子棋',
      capacity: 2,
      basePort: 0,
      enableDiscovery: false,
    );
    expect(await host.start(), isTrue);

    final client = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(client.connect());
    await until(() => client.phase == RoomClientPhase.gameStarting);

    final hostCtrl = GomokuOnlineController.host(host, boardSize: 15);
    final clientCtrl = GomokuOnlineController.client(client);

    // 黑沿横向连五（白零散应一手）：黑 (3,3)..(7,3)
    final blackMoves = [(3, 3), (4, 3), (5, 3), (6, 3), (7, 3)];
    final whiteMoves = [(3, 4), (4, 4), (5, 4), (6, 4)];
    for (var i = 0; i < blackMoves.length; i++) {
      expect(hostCtrl.submitStone(blackMoves[i].$1, blackMoves[i].$2), isTrue);
      await until(() => clientCtrl.moves.length == i * 2 + 1);
      if (i < whiteMoves.length) {
        expect(
          clientCtrl.submitStone(whiteMoves[i].$1, whiteMoves[i].$2),
          isTrue,
        );
        await until(() => hostCtrl.moves.length == i * 2 + 2);
      }
    }

    // 最后一手黑落成五连：双方判定座位 1（黑）胜
    await until(() => clientCtrl.winnerSeat == 1);
    expect(hostCtrl.winnerSeat, 1);
    // 终局后双方均不可再落子
    expect(hostCtrl.isMyTurn, isFalse);
    expect(clientCtrl.isMyTurn, isFalse);
    expect(hostCtrl.submitStone(0, 0), isFalse);

    hostCtrl.dispose();
    clientCtrl.dispose();
  });

  test('对方离开：对局结束且不判胜负（与单词PK一致）', () async {
    final host = RoomHost(
      gameName: '五子棋',
      capacity: 2,
      basePort: 0,
      enableDiscovery: false,
    );
    expect(await host.start(), isTrue);

    final client = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(client.connect());
    await until(() => client.phase == RoomClientPhase.gameStarting);

    final hostCtrl = GomokuOnlineController.host(host, boardSize: 15);
    final clientCtrl = GomokuOnlineController.client(client);

    // 对局进行中客户端退出（关闭底层连接）：房主对局结束，无胜方
    expect(hostCtrl.submitStone(7, 7), isTrue);
    await until(() => clientCtrl.moves.length == 1);
    await client.close();
    await until(() => hostCtrl.gameEndedText != null);
    expect(hostCtrl.gameEndedText, '其他玩家均已离开，对局结束');
    expect(hostCtrl.winnerSeat, isNull);
    expect(hostCtrl.isMyTurn, isFalse); // 终局禁落

    hostCtrl.dispose();
  });

  test('房主解散终局：客户端对局终止并提示', () async {
    final host = RoomHost(
      gameName: '五子棋',
      capacity: 2,
      basePort: 0,
      enableDiscovery: false,
    );
    expect(await host.start(), isTrue);

    final client = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(client.connect());
    await until(() => client.phase == RoomClientPhase.gameStarting);

    final hostCtrl = GomokuOnlineController.host(host, boardSize: 15);
    final clientCtrl = GomokuOnlineController.client(client);

    // 房主退出（控制器销毁）-> 客户端收到终局提示
    hostCtrl.dispose();
    await until(() => clientCtrl.gameEndedText != null);
    expect(clientCtrl.gameEndedText, '房主已解散房间');

    clientCtrl.dispose();
  });

  test('悔棋协商（同意）：双端各回退一手、协商状态复位', () async {
    final (hostCtrl, clientCtrl) = await setupGame({'boardSize': 15});

    // 落两手：黑 (7,7)、白 (8,8)
    expect(hostCtrl.submitStone(7, 7), isTrue);
    await until(() => clientCtrl.moves.length == 1);
    expect(clientCtrl.submitStone(8, 8), isTrue);
    await until(() => hostCtrl.moves.length == 2);

    // 房主发起悔棋：客户端进入待应答状态
    hostCtrl.requestUndo();
    await until(() => clientCtrl.undoState == UndoState.peerRequesting);
    expect(hostCtrl.undoState, UndoState.awaitingPeer);

    // 客户端同意：双端各回退一手（撤销白 (8,8)），回到白方回合
    clientCtrl.respondUndo(true);
    await until(() => hostCtrl.moves.length == 1);
    expect(clientCtrl.moves.length, 1);
    expect(hostCtrl.undoState, UndoState.idle);
    expect(clientCtrl.undoState, UndoState.idle);
    expect(clientCtrl.isMyTurn, isTrue); // 被撤销的是白棋，仍轮到白方

    // 回退后白方可立即重新落子
    expect(clientCtrl.submitStone(8, 8), isTrue);
    await until(() => hostCtrl.moves.length == 2);

    hostCtrl.dispose();
    clientCtrl.dispose();
  });

  test('悔棋协商（拒绝）：棋盘不变、请求方收到提示', () async {
    final (hostCtrl, clientCtrl) = await setupGame({'boardSize': 15});
    final hints = hintsOf(clientCtrl);

    expect(hostCtrl.submitStone(7, 7), isTrue);
    await until(() => clientCtrl.moves.length == 1);

    // 客户端发起悔棋 -> 房主拒绝：双端棋盘保持一手，请求方（客户端）收到提示
    clientCtrl.requestUndo();
    await until(() => hostCtrl.undoState == UndoState.peerRequesting);
    hostCtrl.respondUndo(false);
    await until(() => hints.isNotEmpty);
    expect(hints.last, '对方拒绝了悔棋请求');
    expect(hostCtrl.moves.length, 1);
    expect(clientCtrl.moves.length, 1);
    expect(hostCtrl.undoState, UndoState.idle);
    expect(clientCtrl.undoState, UndoState.idle);

    hostCtrl.dispose();
    clientCtrl.dispose();
  });

  test('认输：客户端认输判房主获胜，双方终局一致', () async {
    final (hostCtrl, clientCtrl) = await setupGame({'boardSize': 15});

    expect(hostCtrl.submitStone(7, 7), isTrue);
    await until(() => clientCtrl.moves.length == 1);

    // 客户端认输：房主获胜并广播，双端状态一致
    clientCtrl.resign();
    await until(() => hostCtrl.winnerSeat == 1);
    await until(() => clientCtrl.winnerSeat == 1);
    expect(hostCtrl.wonByResign, isTrue);
    expect(clientCtrl.wonByResign, isTrue);
    expect(hostCtrl.isMyTurn, isFalse); // 终局禁落
    expect(clientCtrl.isMyTurn, isFalse);

    hostCtrl.dispose();
    clientCtrl.dispose();
  });

  test('房主认输：判客户端获胜', () async {
    final (hostCtrl, clientCtrl) = await setupGame({'boardSize': 15});

    expect(hostCtrl.submitStone(7, 7), isTrue);
    await until(() => clientCtrl.moves.length == 1);

    hostCtrl.resign();
    await until(() => clientCtrl.winnerSeat == 2);
    expect(hostCtrl.winnerSeat, 2);
    expect(hostCtrl.wonByResign, isTrue);

    hostCtrl.dispose();
    clientCtrl.dispose();
  });
}
