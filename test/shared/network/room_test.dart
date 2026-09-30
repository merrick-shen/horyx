import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/shared/network/net_message.dart';
import 'package:horyx/shared/network/net_protocol.dart';
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
      hostName: null,
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
      hostName: null,
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
      hostName: null,
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
      hostName: null,
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

  test('名字同步：hello 带 name 时全量表与增量广播一致', () async {
    final host = RoomHost(
      gameName: '单词PK',
      hostName: '房主甲',
      capacity: 3,
      basePort: 0,
    );
    expect(await host.start(), isTrue);

    final clientA = RoomClient(
      host: '127.0.0.1',
      port: host.port,
      myName: '小明',
    );
    unawaited(clientA.connect());
    await until(() => clientA.phase == RoomClientPhase.joined);
    // joinResponse 全量：含房主名与自己的名字
    expect(clientA.seatNames, {1: '房主甲', 2: '小明'});
    expect(host.nameOf(2), '小明');

    final clientB = RoomClient(
      host: '127.0.0.1',
      port: host.port,
      myName: '小红',
    );
    unawaited(clientB.connect());
    await until(() => clientB.mySeat == 3);
    // B 的 joinResponse 全量含 A 的名字；A 经 playerJoined 增量获知 B
    expect(clientB.seatNames, {1: '房主甲', 2: '小明', 3: '小红'});
    await until(() => clientA.seatNames[3] == '小红');

    await host.close();
    await clientA.close();
    await clientB.close();
  });

  test('名字容错：hello 缺失/非法名字不拒绝连接，回退「玩家N」', () async {
    final host = RoomHost(
      gameName: '单词PK',
      hostName: null,
      capacity: 3,
      basePort: 0,
    );
    expect(await host.start(), isTrue);

    // 缺 name（myName 为 null）不拒绝入座，以「玩家2」兜底入表
    final clientA = RoomClient(host: '127.0.0.1', port: host.port);
    unawaited(clientA.connect());
    await until(() => clientA.phase == RoomClientPhase.joined);
    expect(clientA.mySeat, 2);
    expect(host.nameOf(2), '玩家2');

    // 非法 name（超 12 字素）同样兜底；房主未设置名字时按「玩家 1」兜底
    final clientB = RoomClient(
      host: '127.0.0.1',
      port: host.port,
      myName: '一二三四五六七八九十十一十二十三',
    );
    unawaited(clientB.connect());
    await until(() => clientB.mySeat == 3);
    expect(host.nameOf(3), '玩家3');
    expect(host.nameOf(1), '玩家 1');

    await host.close();
    await clientA.close();
    await clientB.close();
  });

  test('名字随离开清理，补位玩家的名字生效', () async {
    // 容量 4：三人入座不触发满员开局，保证 A 离开后 C 仍可补位
    final host = RoomHost(
      gameName: '单词PK',
      hostName: '房主甲',
      capacity: 4,
      basePort: 0,
    );
    expect(await host.start(), isTrue);

    final clientA = RoomClient(
      host: '127.0.0.1',
      port: host.port,
      myName: '小明',
    );
    unawaited(clientA.connect());
    await until(() => clientA.phase == RoomClientPhase.joined);

    final clientB = RoomClient(
      host: '127.0.0.1',
      port: host.port,
      myName: '小红',
    );
    unawaited(clientB.connect());
    await until(() => clientB.mySeat == 3);
    await until(() => clientA.seatNames[3] == '小红');

    // A 退出：座位 2 的名字随座位一并清理，B 的快照同步移除
    await clientA.close();
    await until(() => !clientB.seatNames.containsKey(2));
    expect(host.nameOf(2), '玩家 2');

    // C 补位 2 号：joinResponse 与增量广播均携带新名字
    final clientC = RoomClient(
      host: '127.0.0.1',
      port: host.port,
      myName: '小刚',
    );
    unawaited(clientC.connect());
    await until(() => clientC.mySeat == 2);
    expect(host.nameOf(2), '小刚');
    await until(() => clientB.seatNames[2] == '小刚');
    expect(clientC.seatNames, {1: '房主甲', 2: '小刚', 3: '小红'});

    await host.close();
    await clientB.close();
    await clientC.close();
  });

  test('解散后迟到的 hello 不再入座，未握手连接随解散一并关闭', () async {
    final host = RoomHost(
      gameName: '单词PK',
      hostName: null,
      capacity: 2,
      basePort: 0,
    );
    expect(await host.start(), isTrue);

    // RoomClient.connect 会立即发 hello，无法停留在"已连接未握手"窗口，
    // 用原始 Socket 模拟该状态（对应房主 _onAccept 已接受、hello 在途）
    final raw = await Socket.connect('127.0.0.1', host.port);
    final received = <NetMessage>[];
    final decoder = NetFrameDecoder();
    final closed = Completer<void>();
    void markClosed() {
      if (!closed.isCompleted) closed.complete();
    }

    raw.listen(
      (chunk) => received.addAll(decoder.feed(chunk)),
      onDone: markClosed,
      // 房主销毁连接时对端可能表现为异常而非流结束，同样视为已关闭
      onError: (Object _) => markClosed(),
    );
    // 留出 accept 处理时间，确保连接已进入房主的握手名单
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await host.close();
    // 解散应关闭未握手连接（bye 或直接销毁），对端读到流结束
    await closed.future.timeout(const Duration(seconds: 3));

    // 解散后再发 hello：修复前会收到 ok:true 的 joinResponse（幽灵入座，
    // 客户端永久卡等待页）；修复后不得入座、不得有任何加入应答
    try {
      raw.add(NetProtocol.encode(const NetMessage(type: NetMessageType.hello)));
    } catch (_) {
      // 连接已被房主关闭导致写入失败：同样证明未入座
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      received.where((m) => m.type == NetMessageType.joinResponse),
      isEmpty,
    );
    expect(host.seats, [1]);
    expect(host.closed, isTrue);

    raw.destroy();
  });
}
