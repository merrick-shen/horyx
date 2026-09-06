import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/games/tank/models/tank_player.dart';
import 'package:horyx/games/tank/services/tank_net_models.dart';
import 'package:horyx/shared/network/net_message.dart';

void main() {
  /// 完整链路往返：消息 → JSON 字节 → 解码回消息
  /// （覆盖枚举名与浮点经 JSON 序列化后的真实表现）
  NetMessage jsonRoundtrip(NetMessage message) => NetMessage.fromJson(
        jsonDecode(jsonEncode(message.toJson())) as Map<String, dynamic>,
      );

  group('驾驶输入 tankDrive', () {
    test('正常输入往返保持角度与油门', () {
      const input = TankDriveInput(targetAngle: 1.25, speedFactor: 0.8);

      final restored = parseTankDrive(
        jsonRoundtrip(tankDriveMessage(input)),
      );

      expect(restored, isNotNull);
      expect(restored!.targetAngle, closeTo(1.25, 1e-9));
      expect(restored.speedFactor, closeTo(0.8, 1e-9));
    });

    test('负角度按 2π 归一到 [0, 2π)', () {
      final message = tankDriveMessage(
        const TankDriveInput(targetAngle: -math.pi / 2, speedFactor: 1),
      );

      final angle = message.payload['angle'] as double;
      expect(angle, inExclusiveRange(0, 2 * math.pi));
      expect(angle, closeTo(1.5 * math.pi, 1e-9));
    });

    test('null 输入编码为停车（angle 字段缺失，解码返回 null）', () {
      final restored = parseTankDrive(jsonRoundtrip(tankDriveMessage(null)));

      expect(restored, isNull);
    });

    test('speed 0 带角度为原地转向（往返保持角度）', () {
      const input = TankDriveInput(targetAngle: 2.0, speedFactor: 0);

      final restored = parseTankDrive(
        jsonRoundtrip(tankDriveMessage(input)),
      );

      expect(restored, isNotNull);
      expect(restored!.targetAngle, closeTo(2.0, 1e-9));
      expect(restored.speedFactor, 0);
    });

    test('油门越界（大于 1 / 负数）拒绝', () {
      final over = NetMessage(
        type: NetMessageType.tankDrive,
        payload: {'angle': 0.0, 'speed': 1.5},
      );
      final negative = NetMessage(
        type: NetMessageType.tankDrive,
        payload: {'angle': 0.0, 'speed': -0.1},
      );

      expect(parseTankDrive(over), isNull);
      expect(parseTankDrive(negative), isNull);
    });

    test('字段缺失或类型错误拒绝', () {
      const missing = NetMessage(type: NetMessageType.tankDrive);
      const badType = NetMessage(
        type: NetMessageType.tankDrive,
        payload: {'angle': 'left', 'speed': 0.5},
      );

      expect(parseTankDrive(missing), isNull);
      expect(parseTankDrive(badType), isNull);
    });
  });

  group('开火消息 tankFire / tankFireEvent', () {
    test('开火请求无载荷且类型正确', () {
      final restored = jsonRoundtrip(tankFireMessage());

      expect(restored.type, NetMessageType.tankFire);
      expect(restored.payload, isEmpty);
    });

    test('开火事件往返保持开火方', () {
      final red = parseTankFireEvent(
        jsonRoundtrip(tankFireEventMessage(TankPlayer.red)),
      );
      final green = parseTankFireEvent(
        jsonRoundtrip(tankFireEventMessage(TankPlayer.green)),
      );

      expect(red, TankPlayer.red);
      expect(green, TankPlayer.green);
    });

    test('开火方非法拒绝', () {
      const bad = NetMessage(
        type: NetMessageType.tankFireEvent,
        payload: {'owner': 'blue'},
      );
      const missing = NetMessage(type: NetMessageType.tankFireEvent);

      expect(parseTankFireEvent(bad), isNull);
      expect(parseTankFireEvent(missing), isNull);
    });
  });

  group('状态快照 tankSnapshot', () {
    TankNetSnapshot sample() => TankNetSnapshot(
          redScore: 2,
          greenScore: 3,
          phase: TankBattlePhase.settling,
          redTank: const TankNetTankState(
            x: 1.5,
            y: 6.25,
            angle: math.pi / 4,
            destroyed: true,
          ),
          greenTank: const TankNetTankState(
            x: 8.5,
            y: 0.75,
            angle: -1.5,
            destroyed: false,
          ),
          bullets: const [
            TankNetBulletState(
              id: 1,
              owner: TankPlayer.red,
              x: 2.0,
              y: 3.0,
              angle: 0.0,
            ),
            TankNetBulletState(
              id: 2,
              owner: TankPlayer.green,
              x: 5.5,
              y: 4.5,
              angle: math.pi,
            ),
          ],
        );

    test('快照完整往返保持全部字段', () {
      final restored = TankNetSnapshot.fromMessage(
        jsonRoundtrip(sample().toMessage()),
      );

      expect(restored, isNotNull);
      expect(restored!.redScore, 2);
      expect(restored.greenScore, 3);
      expect(restored.phase, TankBattlePhase.settling);
      expect(restored.redTank.x, closeTo(1.5, 1e-9));
      expect(restored.redTank.y, closeTo(6.25, 1e-9));
      expect(restored.redTank.angle, closeTo(math.pi / 4, 1e-9));
      expect(restored.redTank.destroyed, isTrue);
      expect(restored.greenTank.destroyed, isFalse);
      expect(restored.bullets.length, 2);
      expect(restored.bullets[0].id, 1);
      expect(restored.bullets[0].owner, TankPlayer.red);
      expect(restored.bullets[1].angle, closeTo(math.pi, 1e-9));
    });

    test('空子弹列表往返为空', () {
      final empty = TankNetSnapshot(
        redScore: 0,
        greenScore: 0,
        phase: TankBattlePhase.playing,
        redTank: const TankNetTankState(x: 1, y: 1, angle: 0, destroyed: false),
        greenTank:
            const TankNetTankState(x: 2, y: 2, angle: 0, destroyed: false),
        bullets: const [],
      );

      final restored =
          TankNetSnapshot.fromMessage(jsonRoundtrip(empty.toMessage()));

      expect(restored!.bullets, isEmpty);
    });

    test('任一子弹条目损坏整体丢弃', () {
      final message = sample().toMessage();
      (message.payload['bullets'] as List)[1] = {'id': 'broken'};

      expect(TankNetSnapshot.fromMessage(message), isNull);
    });

    test('坦克缺失 / 比分非法 / 阶段未知拒绝', () {
      final noTank = sample().toMessage()..payload.remove('green');
      final badScore = sample().toMessage()
        ..payload['score'] = ['a', 'b'];
      final badPhase = sample().toMessage()..payload['phase'] = 'paused';

      expect(TankNetSnapshot.fromMessage(noTank), isNull);
      expect(TankNetSnapshot.fromMessage(badScore), isNull);
      expect(TankNetSnapshot.fromMessage(badPhase), isNull);
    });
  });

  group('回合开始 tankRoundStart', () {
    test('往返保持种子规格与比分', () {
      const round = TankNetRoundStart(
        seed: 987654321,
        cols: 10,
        rows: 7,
        redScore: 1,
        greenScore: 4,
      );

      final restored =
          TankNetRoundStart.fromMessage(jsonRoundtrip(round.toMessage()));

      expect(restored!.seed, 987654321);
      expect(restored.cols, 10);
      expect(restored.rows, 7);
      expect(restored.redScore, 1);
      expect(restored.greenScore, 4);
    });

    test('规格非法（非正数网格）拒绝', () {
      const zero = TankNetRoundStart(
        seed: 1,
        cols: 0,
        rows: 7,
        redScore: 0,
        greenScore: 0,
      );

      expect(TankNetRoundStart.fromMessage(zero.toMessage()), isNull);
    });

    test('字段类型错误拒绝', () {
      const bad = TankNetRoundStart(
        seed: 1,
        cols: 10,
        rows: 7,
        redScore: 0,
        greenScore: 0,
      );
      final message = bad.toMessage()..payload['seed'] = 'abc';

      expect(TankNetRoundStart.fromMessage(message), isNull);
    });
  });
}
