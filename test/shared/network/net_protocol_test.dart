import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/shared/network/net_message.dart';
import 'package:horyx/shared/network/net_protocol.dart';
import 'package:horyx/shared/network/net_session.dart';

void main() {
  group('NetMessage 序列化', () {
    test('JSON 往返保持类型与载荷一致', () {
      final message = NetMessage(
        type: NetMessageType.wordSubmit,
        payload: {'word': 'apple', 'player': 1},
      );

      final restored = NetMessage.fromJson(
        jsonDecode(jsonEncode(message.toJson())) as Map<String, dynamic>,
      );

      expect(restored.type, NetMessageType.wordSubmit);
      expect(restored.payload['word'], 'apple');
      expect(restored.payload['player'], 1);
    });

    test('协议版本不符时抛出格式异常', () {
      expect(
        () => NetMessage.fromJson({
          'v': 999,
          'type': 'ping',
          'payload': <String, dynamic>{},
        }),
        throwsFormatException,
      );
    });

    test('未知消息类型时抛出格式异常', () {
      expect(
        () => NetMessage.fromJson({
          'v': NetMessage.protocolVersion,
          'type': 'not_exists',
          'payload': <String, dynamic>{},
        }),
        throwsFormatException,
      );
    });

    test('缺少 type 字段时抛出格式异常', () {
      expect(
        () => NetMessage.fromJson({
          'v': NetMessage.protocolVersion,
          'payload': <String, dynamic>{},
        }),
        throwsFormatException,
      );
    });
  });

  group('NetProtocol 编码', () {
    test('编码为单行 JSON 并以换行结尾', () {
      final bytes = NetProtocol.encode(
        NetMessage(type: NetMessageType.ping),
      );
      final text = utf8.decode(bytes);

      expect(text.endsWith('\n'), isTrue);
      // 单行：除结尾换行外无其他换行符
      expect(text.indexOf('\n'), text.length - 1);
      expect(jsonDecode(text.trim()), isA<Map<String, dynamic>>());
    });

    test('中文载荷编码后可读（UTF-8 原样输出）', () {
      final bytes = NetProtocol.encode(
        NetMessage(
          type: NetMessageType.hello,
          payload: {'name': '小明'},
        ),
      );
      expect(utf8.decode(bytes).contains('小明'), isTrue);
    });
  });

  group('NetFrameDecoder 分帧', () {
    test('完整单行消息正常解码', () {
      final decoder = NetFrameDecoder();
      final messages = decoder.feed(
        NetProtocol.encode(NetMessage(type: NetMessageType.ping)),
      );

      expect(messages, hasLength(1));
      expect(messages.single.type, NetMessageType.ping);
    });

    test('半包：一条消息拆两次喂入仍可解码', () {
      final decoder = NetFrameDecoder();
      final bytes = NetProtocol.encode(
        NetMessage(type: NetMessageType.hello, payload: {'name': '小明'}),
      );

      // 模拟 TCP 半包：前半段先到，此时无完整消息
      final first = decoder.feed(bytes.sublist(0, bytes.length - 5));
      expect(first, isEmpty);

      // 后半段到达后拼出完整行
      final second = decoder.feed(bytes.sublist(bytes.length - 5));
      expect(second, hasLength(1));
      expect(second.single.type, NetMessageType.hello);
      expect(second.single.payload['name'], '小明');
    });

    test('粘包：多条消息一次到达全部切出', () {
      final decoder = NetFrameDecoder();
      final bytes = [
        ...NetProtocol.encode(NetMessage(type: NetMessageType.ping)),
        ...NetProtocol.encode(NetMessage(type: NetMessageType.pong)),
        ...NetProtocol.encode(NetMessage(type: NetMessageType.bye)),
      ];

      final messages = decoder.feed(bytes);
      expect(messages.map((m) => m.type), [
        NetMessageType.ping,
        NetMessageType.pong,
        NetMessageType.bye,
      ]);
    });

    test('空行与坏 JSON 行被容错丢弃', () {
      final decoder = NetFrameDecoder();
      final messages = decoder.feed(utf8.encode('\n{broken json\n'));

      expect(messages, isEmpty);
      // 丢弃坏行后缓冲区清空，后续消息不受影响
      final next = decoder.feed(
        NetProtocol.encode(NetMessage(type: NetMessageType.ping)),
      );
      expect(next, hasLength(1));
    });

    test('非法 UTF-8 字节行被容错丢弃', () {
      final decoder = NetFrameDecoder();
      // 0xFF 为非法 UTF-8 起始字节
      final messages = decoder.feed([0xFF, 0xFE, 0x0A]);

      expect(messages, isEmpty);
    });
  });

  group('NetSession 会话（本地回环真实 Socket）', () {
    late ServerSocket server;

    setUp(() async {
      // 端口 0：由系统分配空闲端口，避免测试间端口冲突
      server = await ServerSocket.bind('127.0.0.1', 0);
    });

    tearDown(() async {
      await server.close();
    });

    test('消息双向收发正常', () async {
      final serverReady = Completer<NetSession>();
      final serverSubs = <StreamSubscription<NetMessage>>[];
      server.listen((socket) {
        final session = NetSession(
          socket,
          pingInterval: const Duration(days: 1),
        );
        session.onDisconnected = () {};
        serverReady.complete(session);
      });

      final clientSocket = await Socket.connect('127.0.0.1', server.port);
      final clientSession = NetSession(
        clientSocket,
        pingInterval: const Duration(days: 1),
      );
      clientSession.onDisconnected = () {};
      final serverSession = await serverReady.future;

      // 客户端 → 服务端
      final serverGot = Completer<NetMessage>();
      serverSubs.add(
        serverSession.messages.listen((m) => serverGot.complete(m)),
      );
      clientSession.send(
        NetMessage(
          type: NetMessageType.wordSubmit,
          payload: {'word': 'apple'},
        ),
      );
      final submitted = await serverGot.future.timeout(
        const Duration(seconds: 5),
      );
      expect(submitted.type, NetMessageType.wordSubmit);
      expect(submitted.payload['word'], 'apple');

      // 服务端 → 客户端
      final clientGot = Completer<NetMessage>();
      final clientSub = clientSession.messages.listen(
        (m) => clientGot.complete(m),
      );
      serverSession.send(
        NetMessage(
          type: NetMessageType.wordResult,
          payload: {'ok': true},
        ),
      );
      final result = await clientGot.future.timeout(
        const Duration(seconds: 5),
      );
      expect(result.type, NetMessageType.wordResult);
      expect(result.payload['ok'], isTrue);

      await clientSub.cancel();
      for (final sub in serverSubs) {
        await sub.cancel();
      }
      await clientSession.close();
      await serverSession.close();
    });

    test('收到 ping 自动回复 pong（心跳对上层透明）', () async {
      // 客户端用裸 socket：只发一行 ping 并监听原始字节，
      // 验证服务端 NetSession 自动回出了 pong 行
      final serverReady = Completer<NetSession>();
      server.listen((socket) {
        final session = NetSession(
          socket,
          pingInterval: const Duration(days: 1),
        );
        session.onDisconnected = () {};
        serverReady.complete(session);
      });

      final clientSocket = await Socket.connect('127.0.0.1', server.port);
      final gotPong = Completer<void>();
      clientSocket.listen((data) {
        if (utf8.decode(data).contains('pong')) gotPong.complete();
      });

      clientSocket.add(
        NetProtocol.encode(NetMessage(type: NetMessageType.ping)),
      );
      await gotPong.future.timeout(const Duration(seconds: 5));

      final serverSession = await serverReady.future;
      await serverSession.close();
      clientSocket.destroy();
    });

    test('对端异常掉线（不发 bye）后触发断线回调', () async {
      final serverReady = Completer<NetSession>();
      server.listen((socket) {
        final session = NetSession(
          socket,
          pingInterval: const Duration(days: 1),
        );
        session.onDisconnected = () {};
        serverReady.complete(session);
      });

      final clientSocket = await Socket.connect('127.0.0.1', server.port);
      final clientSession = NetSession(
        clientSocket,
        pingInterval: const Duration(days: 1),
      );
      clientSession.onDisconnected = () {};
      final serverSession = await serverReady.future;

      final clientGone = Completer<void>();
      serverSession.onDisconnected = () => clientGone.complete();

      // 直接销毁底层 socket，模拟锁屏/断网等异常掉线
      clientSocket.destroy();
      await clientGone.future.timeout(const Duration(seconds: 5));

      await clientSession.close();
      await serverSession.close();
    });

    test('心跳超时未收到对端消息则判掉线', () async {
      final serverReady = Completer<NetSession>();
      server.listen((socket) {
        // 极短心跳周期：50ms 发 ping、200ms 无消息判超时，测试快速收敛
        final session = NetSession(
          socket,
          pingInterval: const Duration(milliseconds: 50),
          heartbeatTimeout: const Duration(milliseconds: 200),
        );
        session.onDisconnected = () {};
        serverReady.complete(session);
      });

      // 客户端裸 socket 且不回 pong：对服务端而言是「静默对端」
      final clientSocket = await Socket.connect('127.0.0.1', server.port);
      clientSocket.listen((_) {});

      final serverSession = await serverReady.future;
      final timeoutFired = Completer<void>();
      serverSession.onDisconnected = () => timeoutFired.complete();

      await timeoutFired.future.timeout(const Duration(seconds: 5));

      clientSocket.destroy();
      await serverSession.close();
    });

    test('主动 close 发送 bye 且断线回调仅触发一次', () async {
      final serverReady = Completer<NetSession>();
      server.listen((socket) {
        final session = NetSession(
          socket,
          pingInterval: const Duration(days: 1),
        );
        session.onDisconnected = () {};
        serverReady.complete(session);
      });

      final clientSocket = await Socket.connect('127.0.0.1', server.port);
      final clientSession = NetSession(
        clientSocket,
        pingInterval: const Duration(days: 1),
      );
      var clientDisconnectCount = 0;
      clientSession.onDisconnected = () => clientDisconnectCount++;
      final serverSession = await serverReady.future;

      final gotBye = Completer<void>();
      final serverSub = serverSession.messages.listen((m) {
        if (m.type == NetMessageType.bye) gotBye.complete();
      });

      await clientSession.close();
      await gotBye.future.timeout(const Duration(seconds: 5));

      // 等 socket 完全关闭，确认回调没有重复触发
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(clientDisconnectCount, 1);

      await serverSub.cancel();
      await serverSession.close();
    });
  });
}
