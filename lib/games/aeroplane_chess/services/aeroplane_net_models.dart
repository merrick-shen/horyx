import 'package:horyx/games/aeroplane_chess/models/aeroplane_board.dart';
import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';
import 'package:horyx/shared/network/net_message.dart';

/// 飞行棋联机消息的编解码层（纯数据，不做任何规则判定）
///
/// 协议分工（房主权威模型）：
/// - 客户端发 [NetMessageType.aeroplaneRollRequest] 请求掷骰，房主在本地
///   生成骰点后广播 [AeroplaneNetRoll]（点数 + 序号）；
/// - 客户端发 [NetMessageType.aeroplaneMoveSubmit]（棋子编号 + 是否飞越）走子，
///   房主引擎判定迁移后广播 [aeroplaneStateMessage]（全量状态快照重同步）；
/// - 序号为房主权威广播（掷骰结果/状态快照共用）的递增序号，客户端按序
///   幂等应用，防御消息重复与乱序；
/// - 所有解码函数对载荷做类型校验：字段缺失/类型不符/取值越界一律返回
///   null，由调用方丢弃该消息（同版本协议下不应发生，防御异常/篡改载荷）。

/// 掷骰结果（房主广播：点数 + 权威序号）
class AeroplaneNetRoll {
  const AeroplaneNetRoll({required this.value, required this.seq});

  /// 骰点（1..6，仅房主侧生成）
  final int value;

  /// 房主权威广播递增序号（客户端按序幂等应用）
  final int seq;

  /// 编码为掷骰结果消息
  NetMessage toMessage() => NetMessage(
        type: NetMessageType.aeroplaneRollResult,
        payload: {'value': value, 'seq': seq},
      );

  /// 从掷骰结果消息解码；骰点越界/序号非正/类型不符返回 null
  static AeroplaneNetRoll? fromMessage(NetMessage message) {
    final p = message.payload;
    final value = p['value'];
    final seq = p['seq'];
    if (value is! int || seq is! int) return null;
    if (value < 1 || value > 6 || seq < 1) return null;
    return AeroplaneNetRoll(value: value, seq: seq);
  }
}

/// 构造掷骰请求消息：客户端 → 房主（无载荷）
NetMessage aeroplaneRollRequestMessage() =>
    const NetMessage(type: NetMessageType.aeroplaneRollRequest);

/// 构造走子提交消息：客户端 → 房主
NetMessage aeroplaneMoveSubmitMessage({
  required int planeId,
  required bool fly,
}) =>
    NetMessage(
      type: NetMessageType.aeroplaneMoveSubmit,
      payload: {'planeId': planeId, 'fly': fly},
    );

/// 从走子提交消息解码；编号缺失/越界返回 null（fly 缺失按不飞越）
({int planeId, bool fly})? parseAeroplaneMoveSubmit(NetMessage message) {
  final p = message.payload;
  final planeId = p['planeId'];
  if (planeId is! int || planeId < 0 || planeId >= AeroplaneBoard.hangarSlots) {
    return null;
  }
  return (planeId: planeId, fly: p['fly'] == true);
}

/// 构造状态快照消息：房主 → 全端（每次迁移后全量重同步）
NetMessage aeroplaneStateMessage({
  required int seq,
  required AeroplaneGameState state,
}) =>
    NetMessage(
      type: NetMessageType.aeroplaneState,
      payload: {'seq': seq, 'state': state.toJson()},
    );

/// 从状态快照消息解码；序号非正/状态缺失或损坏返回 null
({int seq, AeroplaneGameState state})? parseAeroplaneState(
  NetMessage message,
) {
  final p = message.payload;
  final seq = p['seq'];
  final raw = p['state'];
  if (seq is! int || seq < 1 || raw is! Map<String, dynamic>) return null;
  try {
    return (seq: seq, state: AeroplaneGameState.fromJson(raw));
  } on FormatException {
    return null;
  }
}
