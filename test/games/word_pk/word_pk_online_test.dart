import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/network/room_host.dart';
import 'package:horyx/games/word_pk/services/word_pk_online_controller.dart';
import 'package:horyx/games/word_pk/services/word_validator.dart';

/// 单词PK 联机对局集成测试：本机回环真实 TCP 连接
/// 覆盖：满员开局后三方状态同步、校验拒绝路径、
/// 玩家中途退出的回合跳过、开局后加入拒绝、全员离开终局
void main() {
  // 词表为 assets 资源（房主端校验依赖），测试前需完成加载
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await WordValidator.load();
  });

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
  List<String> hintsOf(WordPkOnlineController controller) {
    final hints = <String>[];
    controller.onHint = hints.add;
    return hints;
  }

  test('满员开局后轮流提交：全端单词与回合同步一致', () async {
    final host = RoomHost(gameName: '单词PK', capacity: 3, basePort: 0,
      enableDiscovery: false,
    );
    expect(await host.start(), isTrue);

    final clientA = RoomClient(host: '127.0.0.1', port: host.port);
    final clientB = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(clientA.connect());
    unawaited(clientB.connect());
    await until(() => clientA.phase == RoomClientPhase.gameStarting);
    await until(() => clientB.phase == RoomClientPhase.gameStarting);

    // 开局后各端挂接对局控制器（模拟等待页跳转对局页的时序）
    final hostCtrl = WordPkOnlineController.host(host);
    final ctrlA = WordPkOnlineController.client(clientA);
    final ctrlB = WordPkOnlineController.client(clientB);

    // 玩家 1（房主）提交：全端同步入列，轮换到玩家 2
    expect(hostCtrl.submitWord('apple'), isTrue);
    await until(() => ctrlA.entries.length == 1 && ctrlB.entries.length == 1);
    expect(hostCtrl.currentPlayer, 2);
    expect(ctrlA.currentPlayer, 2);
    expect(ctrlB.currentPlayer, 2);
    expect(ctrlA.entries.first.word, 'apple');
    expect(ctrlA.entries.first.playerIndex, 1);

    // 玩家 2（客户端 A）提交：经房主校验广播，全端轮换到玩家 3
    expect(ctrlA.submitWord('banana'), isTrue);
    await until(() => ctrlB.entries.length == 2 && hostCtrl.entries.length == 2);
    expect(hostCtrl.currentPlayer, 3);
    expect(ctrlA.currentPlayer, 3);
    expect(ctrlA.entries.first.word, 'banana');
    expect(ctrlA.entries.first.playerIndex, 2);

    // 非本人回合提交：本地直接拦截，不发网络消息
    expect(ctrlA.submitWord('cherry'), isFalse, reason: '当前轮到玩家 3，A 应被拦截');

    // 当前输入者（玩家 3）提交：全端轮换回玩家 1
    expect(ctrlB.submitWord('cherry'), isTrue);
    await until(() => hostCtrl.entries.length == 3 && ctrlA.entries.length == 3);
    expect(hostCtrl.currentPlayer, 1);
    expect(ctrlA.currentPlayer, 1);

    hostCtrl.dispose();
    ctrlA.dispose();
    ctrlB.dispose();
  });

  test('校验拒绝：重复与非词表单词由房主回执拒绝原因', () async {
    final host = RoomHost(gameName: '单词PK', capacity: 2, basePort: 0,
      enableDiscovery: false,
    );
    expect(await host.start(), isTrue);

    final client = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(client.connect());
    await until(() => client.phase == RoomClientPhase.gameStarting);

    final hostCtrl = WordPkOnlineController.host(host);
    final clientCtrl = WordPkOnlineController.client(client);
    final hints = hintsOf(clientCtrl);

    // 房主先提交，轮换到客户端；客户端提交重复词被拒
    expect(hostCtrl.submitWord('apple'), isTrue);
    await until(() => clientCtrl.currentPlayer == 2);
    expect(clientCtrl.submitWord('apple'), isTrue);
    await until(() => hints.isNotEmpty);
    expect(hints.last, '单词已重复');
    // 拒绝不改变回合与列表
    expect(clientCtrl.currentPlayer, 2);
    expect(clientCtrl.entries.length, 1);

    // 非词表单词被拒
    hints.clear();
    expect(clientCtrl.submitWord('qqqqzz'), isTrue);
    await until(() => hints.isNotEmpty);
    expect(hints.last, '不是有效的英文单词');

    hostCtrl.dispose();
    clientCtrl.dispose();
  });

  test('玩家中途退出：轮到的玩家离开后回合跳到下一在线座位', () async {
    final host = RoomHost(gameName: '单词PK', capacity: 3, basePort: 0,
      enableDiscovery: false,
    );
    expect(await host.start(), isTrue);

    final clientA = RoomClient(host: '127.0.0.1', port: host.port);
    final clientB = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(clientA.connect());
    unawaited(clientB.connect());
    await until(() => clientA.phase == RoomClientPhase.gameStarting);
    await until(() => clientB.phase == RoomClientPhase.gameStarting);

    final hostCtrl = WordPkOnlineController.host(host);
    final ctrlA = WordPkOnlineController.client(clientA);
    final ctrlB = WordPkOnlineController.client(clientB);

    // 玩家 1 提交后轮到玩家 2，此时玩家 2 退出：回合应跳过 2 直接到 3
    expect(hostCtrl.submitWord('apple'), isTrue);
    await until(() => ctrlA.currentPlayer == 2);
    // 玩家 2 断开连接（模拟退出/掉线）
    await clientA.close();
    await until(() => ctrlB.currentPlayer == 3);
    expect(hostCtrl.currentPlayer, 3);
    // 存活两端状态一致
    expect(ctrlB.entries.length, 1);
    expect(hostCtrl.entries.length, 1);

    hostCtrl.dispose();
    ctrlA.dispose();
    ctrlB.dispose();
  });

  test('开局后加入被拒绝：对局进行中不放新人', () async {
    final host = RoomHost(gameName: '单词PK', capacity: 2, basePort: 0,
      enableDiscovery: false,
    );
    expect(await host.start(), isTrue);

    final clientA = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(clientA.connect());
    await until(() => clientA.phase == RoomClientPhase.gameStarting);

    final clientB = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(clientB.connect());
    await until(() => clientB.phase == RoomClientPhase.failed);
    expect(clientB.failReason, '对局已开始，无法加入');

    await clientA.close();
    await clientB.close();
    await host.close();
  });

  test('全员离开终局：只剩房主时对局结束', () async {
    final host = RoomHost(gameName: '单词PK', capacity: 3, basePort: 0,
      enableDiscovery: false,
    );
    expect(await host.start(), isTrue);

    final clientA = RoomClient(host: '127.0.0.1', port: host.port);
    final clientB = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(clientA.connect());
    unawaited(clientB.connect());
    await until(() => clientA.phase == RoomClientPhase.gameStarting);
    await until(() => clientB.phase == RoomClientPhase.gameStarting);

    final hostCtrl = WordPkOnlineController.host(host);
    expect(hostCtrl.gameEndedText, isNull);

    // 两名客户端先后退出：最后一人退出时触发全员离开终局
    await clientA.close();
    expect(hostCtrl.gameEndedText, isNull);
    await clientB.close();
    await until(() => hostCtrl.gameEndedText != null);
    expect(hostCtrl.gameEndedText, '其他玩家均已离开，对局结束');

    hostCtrl.dispose();
  });

  test('房主解散终局：客户端对局终止并提示', () async {
    final host = RoomHost(gameName: '单词PK', capacity: 2, basePort: 0,
      enableDiscovery: false,
    );
    expect(await host.start(), isTrue);

    final client = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(client.connect());
    await until(() => client.phase == RoomClientPhase.gameStarting);

    final hostCtrl = WordPkOnlineController.host(host);
    final clientCtrl = WordPkOnlineController.client(client);

    // 房主退出（控制器销毁）-> 客户端收到终局提示
    hostCtrl.dispose();
    await until(() => clientCtrl.gameEndedText != null);
    expect(clientCtrl.gameEndedText, '房主已解散房间');

    clientCtrl.dispose();
  });
}
