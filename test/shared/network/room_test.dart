import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/network/room_host.dart';

/// 局域网房间集成测试：本机回环真实 TCP 连接
/// 覆盖：建房入座、座位广播、满员开局、满员拒绝、玩家退出、房主解散
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

  test('建房与加入：座位分配、入座广播与满员自动开局', () async {
    // basePort 0：系统分配临时端口，避免与真实服务端口冲突
    final host = RoomHost(
      gameName: '单词PK',
      capacity: 3,
      basePort: 0,
    );
    expect(await host.start(), isTrue);
    expect(host.port, greaterThan(0));

    final clientA = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(clientA.connect());
    await until(() => clientA.phase == RoomClientPhase.joined);
    expect(clientA.mySeat, 2);
    expect(clientA.capacity, 3);
    expect(clientA.seats, [1, 2]);
    expect(host.seats, [1, 2]);

    // 第二位玩家加入：joinResponse 与满员 gameStart 背靠背到达，
    // 等具体阶段（joined）会错过，改等稳定的座位号
    final clientB = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(clientB.connect());
    await until(() => clientB.mySeat == 3);
    expect(clientB.capacity, 3);
    // 自己的座位应包含在座位快照中（等待页渲染依据）
    expect(clientB.seats, [1, 2, 3]);
    await until(() => clientA.seats.contains(3));

    // 满 3 人自动开局：双方均进入 gameStarting
    await until(() => clientA.phase == RoomClientPhase.gameStarting);
    await until(() => clientB.phase == RoomClientPhase.gameStarting);
    expect(host.gameStarted, isTrue);
    expect(host.seats, [1, 2, 3]);

    await host.close();
    await clientA.close();
    await clientB.close();
  });

  test('开局后拒绝：对局已开始时的加入请求被拒绝并断开', () async {
    final host = RoomHost(
      gameName: '单词PK',
      capacity: 2,
      basePort: 0,
    );
    expect(await host.start(), isTrue);

    final clientA = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(clientA.connect());
    // 容量 2：A 入座后即满员并自动开局
    await until(() => clientA.phase == RoomClientPhase.gameStarting);

    // 满员即开局，后续加入统一按「对局已开始」拒绝
    final clientB = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(clientB.connect());
    await until(() => clientB.phase == RoomClientPhase.failed);
    expect(clientB.failReason, '对局已开始，无法加入');

    await host.close();
    await clientA.close();
    await clientB.close();
  });

  test('玩家退出：房主清理座位并广播给其他玩家', () async {
    final host = RoomHost(
      gameName: '单词PK',
      capacity: 4,
      basePort: 0,
    );
    expect(await host.start(), isTrue);

    final clientA = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(clientA.connect());
    await until(() => clientA.phase == RoomClientPhase.joined);

    final clientB = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(clientB.connect());
    await until(() => clientB.phase == RoomClientPhase.joined);
    await until(() => clientA.seats.contains(3));

    // A 主动退出：房主移除 2 号座位，B 收到 playerLeft 后座位快照同步收缩
    await clientA.close();
    await until(() => !host.seats.contains(2));
    await until(() => !clientB.seats.contains(2));
    // B 仍在座（3 号位），房主只剩 1、3 号
    expect(host.seats, [1, 3]);
    expect(clientB.seats, [1, 3]);

    await host.close();
    await clientB.close();
  });

  test('房主解散：已加入的玩家收到断开提示（bye 区分主动解散）', () async {
    final host = RoomHost(
      gameName: '单词PK',
      capacity: 3,
      basePort: 0,
    );
    expect(await host.start(), isTrue);

    final client = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(client.connect());
    await until(() => client.phase == RoomClientPhase.joined);

    await host.close();
    await until(() => client.phase == RoomClientPhase.disconnected);
    expect(client.disconnectText, '房主已解散房间');

    await client.close();
  });

  test('地址不可达：连接失败给出用户可读原因', () async {
    // 127.0.0.1 上几乎不可能有监听的端口（绑定失败率极高）；
    // 用保留端口段进一步降低碰撞概率
    final client = RoomClient(host: '127.0.0.1', port: 1);
    await client.connect();
    expect(client.phase, RoomClientPhase.failed);
    expect(client.failReason, contains('无法连接'));
  });
}
