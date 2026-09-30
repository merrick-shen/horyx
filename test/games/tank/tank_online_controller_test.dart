import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/games/tank/engine/tank_maze_game.dart';
import 'package:horyx/games/tank/models/tank_maze.dart';
import 'package:horyx/games/tank/models/tank_player.dart';
import 'package:horyx/games/tank/services/tank_online_controller.dart';
import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/network/room_host.dart';

/// 坦克联机控制器集成测试：本机回环真实 TCP（与 room_test 同模式）
///
/// 覆盖：回合种子同步（双端同迷宫）、比分随回合同步与页面通知、
/// 输入上报链路不崩、对方退出/房主解散的终局传播。
/// 战场（TankMazeGame）仅构造不挂载——Flame onLoad 未跑，坦克实体
/// 不存在：快照广播在坦克就绪前自动跳过（回合链路不受影响），
/// 快照驱动的完整验证留给真机联调（第 4/5 步）
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

  /// 建一个满员双人房间并接管双方控制器（连接与挂接就绪）
  Future<(RoomHost, RoomClient, TankOnlineController, TankOnlineController)>
      setUpRoom() async {
    final host = RoomHost(
      gameName: '坦克动荡',
      hostName: null,
      capacity: 2,
      basePort: 0,
    );
    expect(await host.start(), isTrue);
    final client = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(client.connect());
    // 容量 2：入座即满员开局
    await until(() => client.phase == RoomClientPhase.gameStarting);
    final hostController = TankOnlineController.host(host);
    final clientController = TankOnlineController.client(client);
    // 控制器销毁会关闭底层连接（基类统一负责）
    addTearDown(hostController.dispose);
    addTearDown(clientController.dispose);
    return (host, client, hostController, clientController);
  }

  test('回合种子同步：房主广播首局迷宫，客户端挂接后重建同一迷宫与比分', () async {
    final (_, _, hostController, clientController) = await setUpRoom();

    // 房主战场先于客户端就绪：构造时迷宫与比分即可读（挂载非必需）
    final hostGame = TankMazeGame(maze: TankMaze.generate());
    hostGame
      ..redScore = 3
      ..greenScore = 2;

    // 客户端收到回合消息（战场未挂接 → 暂存）：比分通知先行触达页面
    var notified = 0;
    clientController.addListener(() => notified++);
    hostController.attachHostGame(hostGame);
    await until(() => notified > 0);

    // 客户端战场就绪：暂存的回合消息应用 → 同种子重建同一迷宫
    final clientGame = TankMazeGame(maze: TankMaze.generate(), remote: true);
    expect(clientGame.maze.seed, isNot(hostGame.maze.seed),
        reason: '挂接前是本地占位迷宫，与房主迷宫无关');
    clientController.attachClientGame(clientGame);
    expect(clientGame.maze.seed, hostGame.maze.seed);
    expect(clientGame.maze.cols, hostGame.maze.cols);
    expect(clientGame.maze.rows, hostGame.maze.rows);
    expect(clientGame.redScore, 3);
    expect(clientGame.greenScore, 2);
  });

  test('房主新局事件：结算后自动开新局时广播新种子', () async {
    final (_, _, hostController, clientController) = await setUpRoom();

    final hostGame = TankMazeGame(maze: TankMaze.generate());
    hostController.attachHostGame(hostGame);

    final clientGame = TankMazeGame(maze: TankMaze.generate(), remote: true);
    clientController.attachClientGame(clientGame);
    final firstSeed = clientGame.maze.seed;

    // 模拟结算期结束后的自动开新局：战场换新迷宫并触发回调 →
    // 房主广播新种子 → 客户端（已挂接，无需暂存）直接重建
    hostGame
      ..maze = TankMaze.generate()
      ..onRoundStart?.call();
    await until(() => clientGame.maze.seed != firstSeed);
    expect(clientGame.maze.seed, hostGame.maze.seed);
  });

  test('输入上报：驾驶与开火消息按协议送达房主侧不崩', () async {
    final (_, _, hostController, clientController) = await setUpRoom();

    final hostGame = TankMazeGame(maze: TankMaze.generate());
    hostController.attachHostGame(hostGame);

    // 客户端发送各类输入（战场未挂接/坦克未就绪时房主侧应为空安全跳过）：
    // 覆盖 onHostGameMessage 的解码与转发路径，不崩即通过
    clientController
      ..sendDrive(const TankDriveInput(targetAngle: 0.5, speedFactor: 1))
      ..sendFire()
      ..sendDrive(null)
      ..sendDrive(const TankDriveInput(targetAngle: 2.0, speedFactor: 0.5));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  test('对方离开：客户端退出后房主进入终局（无胜负）', () async {
    final (host, client, hostController, _) = await setUpRoom();
    // host 连接的关闭由控制器 dispose 统一负责（RoomHost.close 幂等），
    // 此处不得再 addTearDown(host.dispose)：ChangeNotifier 先被销毁的话，
    // 控制器 dispose 触发的 close → notifyListeners 会命中已销毁断言

    await client.close();
    await until(() => hostController.gameEndedText != null);
    expect(hostController.gameEndedText, '其他玩家均已离开，对局结束');
  });

  test('房主解散：客户端收到连接断开进入终局', () async {
    final (host, _, _, clientController) = await setUpRoom();

    await host.close();
    await until(() => clientController.gameEndedText != null);
    expect(clientController.gameEndedText, isNotNull);
  });
}
