import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/models/chess_piece.dart';
import 'package:horyx/games/chess/services/chess_online_controller.dart';
import 'package:horyx/games/chess/services/chess_rules.dart';
import 'package:horyx/shared/network/net_message.dart';
import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/network/room_host.dart';

/// 中国象棋联机对局集成测试：本机回环真实 TCP 连接
/// 覆盖：开局双端棋盘一致、轮流走子同步（含吃子）、非法提交本地拦截与
/// 房主终极校验、将死双端同判（重炮杀实战序列）、对方离开/房主解散终局、
/// 悔棋协商（同意/拒绝/B9 规则）、认输终局
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
  List<String> hintsOf(ChessOnlineController controller) {
    final hints = <String>[];
    controller.onHint = hints.add;
    return hints;
  }

  // 建房 + 加入 + 双端挂控制器的通用前置（各用例仅一步之遥）
  // 象棋无规格选项，gameStartPayload 为空对象
  Future<(ChessOnlineController, ChessOnlineController)> setupGame() async {
    final host = RoomHost(
      gameName: '中国象棋',
      capacity: 2,
      basePort: 0,
      gameStartPayload: const {},
    );
    expect(await host.start(), isTrue);
    final client = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(client.connect());
    await until(() => client.phase == RoomClientPhase.gameStarting);
    return (
      ChessOnlineController.host(host),
      ChessOnlineController.client(client),
    );
  }

  test('开局双端棋盘一致：房主执红先行，客户端执黑', () async {
    final (hostCtrl, clientCtrl) = await setupGame();

    // 双端从同一初始局面开始（象棋无开局规格参数）
    expect(hostCtrl.board.encode(), ChessBoard.initial().encode());
    expect(clientCtrl.board.encode(), hostCtrl.board.encode());
    expect(hostCtrl.myColor, ChessColor.red);
    expect(clientCtrl.myColor, ChessColor.black);
    expect(hostCtrl.isMyTurn, isTrue); // 红先，房主先行
    expect(clientCtrl.isMyTurn, isFalse);
    expect(hostCtrl.winnerText, isNull);

    hostCtrl.dispose();
    clientCtrl.dispose();
  });

  test('轮流走子双端同步：走子、吃子与轮次轮换正确', () async {
    final (hostCtrl, clientCtrl) = await setupGame();

    // 红炮二平五：双端同步，轮到客户端
    expect(hostCtrl.submitMove((from: (1, 2), to: (4, 2))), isTrue);
    await until(() => clientCtrl.moves.length == 1);
    expect(clientCtrl.moves.single, (from: (1, 2), to: (4, 2)));
    expect(clientCtrl.isMyTurn, isTrue);
    expect(hostCtrl.isMyTurn, isFalse);

    // 黑炮8平5：双端同步，轮回房主
    expect(clientCtrl.submitMove((from: (1, 7), to: (4, 7))), isTrue);
    await until(() => hostCtrl.moves.length == 2);

    // 红炮五进四吃黑中卒：双端棋盘编码一致，被吃子同步消失
    expect(hostCtrl.submitMove((from: (4, 2), to: (4, 6))), isTrue);
    await until(() => clientCtrl.moves.length == 3);
    expect(clientCtrl.board.encode(), hostCtrl.board.encode());
    final cannon = clientCtrl.board.pieceAt((4, 6));
    expect(cannon?.color, ChessColor.red);
    expect(cannon?.type, ChessPieceType.cannon);
    expect(clientCtrl.isMyTurn, isTrue); // 黑方行棋

    hostCtrl.dispose();
    clientCtrl.dispose();
  });

  test('非法提交被拒：非本人回合与非法走法（本地拦截）', () async {
    final (hostCtrl, clientCtrl) = await setupGame();
    final hints = hintsOf(clientCtrl);

    // 红先：客户端（黑）此刻提交被本地拦截，不发网络消息
    expect(clientCtrl.submitMove((from: (1, 7), to: (4, 7))), isFalse);
    expect(hints, contains('还没轮到你走子'));

    // 房主先走一步后轮到客户端
    expect(hostCtrl.submitMove((from: (1, 2), to: (4, 2))), isTrue);
    await until(() => clientCtrl.moves.length == 1);

    // 黑仕平走（仕只能斜行）：本地拦截
    hints.clear();
    expect(clientCtrl.submitMove((from: (3, 9), to: (3, 8))), isFalse);
    expect(hints, contains('这不是合法走法'));

    // 起点无棋子：本地拦截
    expect(clientCtrl.submitMove((from: (0, 5), to: (0, 4))), isFalse);
    expect(hints, contains('这不是合法走法'));

    // 吃己方棋子（黑炮吃黑马）：本地拦截
    expect(clientCtrl.submitMove((from: (1, 7), to: (1, 9))), isFalse);
    expect(hints, contains('这不是合法走法'));
    expect(clientCtrl.board.encode(), hostCtrl.board.encode()); // 棋盘未污染

    hostCtrl.dispose();
    clientCtrl.dispose();
  });

  test('房主侧终极校验：绕过本地拦截的非法提交被回执拒绝', () async {
    // 该用例需直接走网络层发消息（模拟绕过本地拦截），内联建房持有原始连接
    final host = RoomHost(
      gameName: '中国象棋',
      capacity: 2,
      basePort: 0,
      gameStartPayload: const {},
    );
    expect(await host.start(), isTrue);
    final client = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(client.connect());
    await until(() => client.phase == RoomClientPhase.gameStarting);
    final hostCtrl = ChessOnlineController.host(host);
    final clientCtrl = ChessOnlineController.client(client);
    final hints = hintsOf(clientCtrl);

    // 直接走网络层发 moveSubmit（模拟恶意/异版客户端绕过本地拦截）：
    // 黑方（座位2）在红方回合提交 -> 房主回执 notYourTurn
    client.send(
      const NetMessage(
        type: NetMessageType.moveSubmit,
        payload: {'fromCol': 1, 'fromRow': 7, 'toCol': 4, 'toRow': 7},
      ),
    );
    await until(() => hints.isNotEmpty);
    expect(hints.last, '还没轮到你走子');
    expect(hostCtrl.moves, isEmpty); // 棋盘未被污染

    // 房主走子后，客户端提交以红方棋子为起点（替对方走子）-> invalidMove
    expect(hostCtrl.submitMove((from: (1, 2), to: (4, 2))), isTrue);
    await until(() => clientCtrl.moves.length == 1);
    hints.clear();
    client.send(
      const NetMessage(
        type: NetMessageType.moveSubmit,
        payload: {'fromCol': 4, 'fromRow': 2, 'toCol': 4, 'toRow': 6},
      ),
    );
    await until(() => hints.isNotEmpty);
    expect(hints.last, '这不是合法走法');
    expect(hostCtrl.moves.length, 1);

    // 坐标越界的提交被解析层静默丢弃（无回执、不崩溃、不污染棋盘）
    client.send(
      const NetMessage(
        type: NetMessageType.moveSubmit,
        payload: {'fromCol': 1, 'fromRow': 7, 'toCol': 9, 'toRow': 99},
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(hints.length, 1); // 未新增提示
    expect(hostCtrl.moves.length, 1);

    hostCtrl.dispose();
    clientCtrl.dispose();
  });

  test('将死终局：双端同判且停止走子（重炮杀实战序列）', () async {
    final (hostCtrl, clientCtrl) = await setupGame();

    // 实战将死线（红四步重炮杀，黑配合）：炮二平五 / 炮8平5 /
    // 炮五进四（吃卒将军）/ 炮5平4 / 炮八进二 / 卒1进1 / 炮八平五（将死）
    final line = [
      ((1, 2), (4, 2)), // 红炮二平五
      ((1, 7), (4, 7)), // 黑炮8平5
      ((4, 2), (4, 6)), // 红炮五进四（吃卒，将军）
      ((4, 7), (5, 7)), // 黑炮平开解将
      ((7, 2), (7, 4)), // 红炮八进二
      ((0, 6), (0, 5)), // 黑卒1进1
      ((7, 4), (4, 4)), // 红炮八平五（重炮将死）
    ];
    for (var i = 0; i < line.length; i++) {
      final (from, to) = line[i];
      final mover = i.isEven ? hostCtrl : clientCtrl;
      final other = i.isEven ? clientCtrl : hostCtrl;
      expect(mover.submitMove((from: from, to: to)), isTrue,
          reason: '第 ${i + 1} 手应为合法走法');
      await until(() => other.moves.length == i + 1);
    }

    // 最后一手红炮构成重炮将死：双方判定座位 1（红）胜，原因为将死
    await until(() => clientCtrl.winnerSeat == 1);
    expect(hostCtrl.winnerSeat, 1);
    expect(hostCtrl.winReason, ChessEndReason.checkmate);
    expect(clientCtrl.winReason, ChessEndReason.checkmate);
    expect(hostCtrl.winnerText, '红方');
    // 终局后双方均不可再走子
    expect(hostCtrl.isMyTurn, isFalse);
    expect(clientCtrl.isMyTurn, isFalse);
    expect(hostCtrl.submitMove((from: (4, 0), to: (4, 1))), isFalse);

    hostCtrl.dispose();
    clientCtrl.dispose();
  });

  test('对方离开：对局结束且不判胜负（与单词PK/五子棋一致）', () async {
    // 该用例需直接关闭底层连接，内联建房持有原始连接
    final host = RoomHost(
      gameName: '中国象棋',
      capacity: 2,
      basePort: 0,
      gameStartPayload: const {},
    );
    expect(await host.start(), isTrue);
    final client = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(client.connect());
    await until(() => client.phase == RoomClientPhase.gameStarting);
    final hostCtrl = ChessOnlineController.host(host);
    final clientCtrl = ChessOnlineController.client(client);

    // 对局进行中客户端退出（关闭底层连接）：房主对局结束，无胜方
    expect(hostCtrl.submitMove((from: (1, 2), to: (4, 2))), isTrue);
    await until(() => clientCtrl.moves.length == 1);
    await client.close();
    await until(() => hostCtrl.gameEndedText != null);
    expect(hostCtrl.gameEndedText, '其他玩家均已离开，对局结束');
    expect(hostCtrl.winnerSeat, isNull);
    expect(hostCtrl.isMyTurn, isFalse); // 终局禁走

    hostCtrl.dispose();
  });

  test('房主解散终局：客户端对局终止并提示', () async {
    final (hostCtrl, clientCtrl) = await setupGame();

    // 房主退出（控制器销毁）-> 客户端收到终局提示
    hostCtrl.dispose();
    await until(() => clientCtrl.gameEndedText != null);
    expect(clientCtrl.gameEndedText, '房主已解散房间');

    clientCtrl.dispose();
  });

  test('悔棋协商（同意）：双端各回退一手、协商状态复位', () async {
    final (hostCtrl, clientCtrl) = await setupGame();

    // 走两手：红炮二平五、黑炮8平5
    expect(hostCtrl.submitMove((from: (1, 2), to: (4, 2))), isTrue);
    await until(() => clientCtrl.moves.length == 1);
    expect(clientCtrl.submitMove((from: (1, 7), to: (4, 7))), isTrue);
    await until(() => hostCtrl.moves.length == 2);

    // 轮到红方（房主），由客户端发起悔棋（悔自己的黑炮）
    clientCtrl.requestUndo();
    await until(() => hostCtrl.undoState == UndoState.peerRequesting);
    expect(clientCtrl.undoState, UndoState.awaitingPeer);

    // 房主同意：双端各回退一手（撤销黑炮），回到红方回合
    // （客户端随 undoApplied 广播异步回退，以客户端为准等待）
    hostCtrl.respondUndo(true);
    await until(() => clientCtrl.moves.length == 1);
    expect(hostCtrl.moves.length, 1);
    expect(hostCtrl.undoState, UndoState.idle);
    expect(clientCtrl.undoState, UndoState.idle);
    // 黑炮还原到起点（被"吃"的子随重放复原，此处为无吃子走子）
    expect(clientCtrl.board.pieceAt((1, 7))?.color, ChessColor.black);
    expect(clientCtrl.board.pieceAt((4, 7)), isNull);
    expect(clientCtrl.isMyTurn, isTrue); // 被撤销的是黑棋，回到黑方回合

    // 回退后黑方可立即重新走子
    expect(clientCtrl.submitMove((from: (1, 7), to: (4, 7))), isTrue);
    await until(() => hostCtrl.moves.length == 2);

    hostCtrl.dispose();
    clientCtrl.dispose();
  });

  test('B9：轮到自己时不可悔棋（悔棋只能悔自己的上一手）', () async {
    final (hostCtrl, clientCtrl) = await setupGame();
    final hostHints = hintsOf(hostCtrl);
    final clientHints = hintsOf(clientCtrl);

    // 一手红棋后轮到黑：黑方（客户端）此刻发起会被拦截并提示
    expect(hostCtrl.submitMove((from: (1, 2), to: (4, 2))), isTrue);
    await until(() => clientCtrl.moves.length == 1);
    clientCtrl.requestUndo();
    await until(() => clientHints.isNotEmpty);
    expect(clientHints.last, '只能在对方回合悔棋（悔自己的上一手）');
    expect(clientCtrl.undoState, UndoState.idle); // 未进入协商

    // 两手后轮到红：红方（房主）发起同样被拦截
    expect(clientCtrl.submitMove((from: (1, 7), to: (4, 7))), isTrue);
    await until(() => hostCtrl.moves.length == 2);
    hostCtrl.requestUndo();
    await until(() => hostHints.isNotEmpty);
    expect(hostHints.last, '只能在对方回合悔棋（悔自己的上一手）');
    expect(hostCtrl.undoState, UndoState.idle);

    hostCtrl.dispose();
    clientCtrl.dispose();
  });

  test('B9：协商期间对方走子，同意后回退到发起时刻快照', () async {
    final (hostCtrl, clientCtrl) = await setupGame();

    // 两手（红黑）后轮到红：客户端发起悔棋（快照 target=1，悔黑炮）
    expect(hostCtrl.submitMove((from: (1, 2), to: (4, 2))), isTrue);
    await until(() => clientCtrl.moves.length == 1);
    expect(clientCtrl.submitMove((from: (1, 7), to: (4, 7))), isTrue);
    await until(() => hostCtrl.moves.length == 2);
    clientCtrl.requestUndo();
    await until(() => hostCtrl.undoState == UndoState.peerRequesting);

    // 协商期间房主仍可走子（轮到红）：走第 3 手
    expect(hostCtrl.submitMove((from: (7, 2), to: (7, 4))), isTrue);
    await until(() => clientCtrl.moves.length == 3);

    // 房主同意：回退到快照（1 手），协商期间的第 3 手一并撤销
    // （客户端随 undoApplied 广播异步回退，以客户端为准等待）
    hostCtrl.respondUndo(true);
    await until(() => clientCtrl.moves.length == 1);
    expect(hostCtrl.moves.length, 1);
    expect(hostCtrl.moves.single, (from: (1, 2), to: (4, 2))); // 仅剩红炮
    expect(clientCtrl.isMyTurn, isTrue); // 黑被撤，回到黑方回合
    expect(hostCtrl.undoState, UndoState.idle);
    expect(clientCtrl.undoState, UndoState.idle);

    hostCtrl.dispose();
    clientCtrl.dispose();
  });

  test('悔棋协商（拒绝）：棋盘不变、请求方收到提示', () async {
    final (hostCtrl, clientCtrl) = await setupGame();
    final hints = hintsOf(hostCtrl);

    expect(hostCtrl.submitMove((from: (1, 2), to: (4, 2))), isTrue);
    await until(() => clientCtrl.moves.length == 1);

    // 轮到黑方（客户端），由房主发起悔棋（悔自己的红炮）-> 客户端拒绝
    hostCtrl.requestUndo();
    await until(() => clientCtrl.undoState == UndoState.peerRequesting);
    clientCtrl.respondUndo(false);
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
    final (hostCtrl, clientCtrl) = await setupGame();

    expect(hostCtrl.submitMove((from: (1, 2), to: (4, 2))), isTrue);
    await until(() => clientCtrl.moves.length == 1);

    // 客户端认输：房主获胜并广播，双端状态一致
    clientCtrl.resign();
    await until(() => hostCtrl.winnerSeat == 1);
    await until(() => clientCtrl.winnerSeat == 1);
    expect(hostCtrl.winReason, ChessEndReason.resign);
    expect(clientCtrl.winReason, ChessEndReason.resign);
    expect(hostCtrl.winnerText, '红方');
    expect(clientCtrl.winnerText, '红方');
    expect(hostCtrl.isMyTurn, isFalse); // 终局禁走
    expect(clientCtrl.isMyTurn, isFalse);

    hostCtrl.dispose();
    clientCtrl.dispose();
  });

  test('房主认输：判客户端获胜', () async {
    final (hostCtrl, clientCtrl) = await setupGame();

    expect(hostCtrl.submitMove((from: (1, 2), to: (4, 2))), isTrue);
    await until(() => clientCtrl.moves.length == 1);

    hostCtrl.resign();
    await until(() => clientCtrl.winnerSeat == 2);
    expect(hostCtrl.winnerSeat, 2);
    expect(hostCtrl.winReason, ChessEndReason.resign);
    expect(clientCtrl.winnerText, '黑方');

    hostCtrl.dispose();
    clientCtrl.dispose();
  });
}
