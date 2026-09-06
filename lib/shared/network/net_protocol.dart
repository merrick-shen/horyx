import 'dart:convert';

import 'package:horyx/shared/network/net_message.dart';

/// 局域网联机协议编解码（NDJSON 协议）
/// 一行一个 UTF-8 JSON 对象，以 \n 分隔：
/// - 编码：消息对象 → 单行 JSON 文本（不含换行）+ \n 结尾
/// - 解码：字节流增量喂入，按 \n 切出完整行再反序列化
///
/// 选 NDJSON 而非二进制协议的原因：
/// json 编解码原生零依赖、Wireshark/日志抓包肉眼可读、调试成本低
abstract final class NetProtocol {
  /// 消息编码为传输字节（单行 JSON + 换行分隔符）
  /// payload 中的中文等非 ASCII 字符保持原样（UTF-8 输出），抓包可读
  static List<int> encode(NetMessage message) =>
      utf8.encode('${jsonEncode(message.toJson())}\n');
}

/// 分帧缓冲溢出：对端持续发送不含换行的字节流（异常或恶意），
/// 由 [NetSession] 捕获后断开连接，防止缓冲无限累积导致 OOM
class NetFrameOverflowException implements Exception {
  const NetFrameOverflowException();

  @override
  String toString() => 'NetFrameDecoder: 半行缓冲超过上限（对端异常字节流）';
}

/// NDJSON 分帧解码器：把无边界的 TCP 字节流切成一行行 JSON 消息
/// TCP 是字节流协议，存在半包（一条消息分多次到达）与
/// 粘包（多条消息一次到达）问题，必须缓冲增量数据按 \n 切分
class NetFrameDecoder {
  /// 行缓冲：累积尚未以 \n 结尾的半行字节
  final List<int> _buffer = [];

  /// 半行缓冲上限：合法消息（最大为坦克 30Hz 状态快照，数 KB 级）
  /// 远小于此值。对端若持续发送不含换行的字节，半行会无限累积直至 OOM
  /// （心跳 15 秒超时前的窗口内可灌入大量数据）——超限即判定对端异常，
  /// 与 RoomClient 待处理游戏消息的 100 条上限属同一防御思路
  static const int _maxBufferBytes = 1 << 20; // 1 MB

  /// 喂入一段原始字节，返回本次切出的完整消息
  /// 解析失败的行（损坏 JSON、版本不符等）直接丢弃不断开连接：
  /// 单条坏消息不足以判定对端异常，宽容处理避免误伤
  ///
  /// 半行累积超过 [_maxBufferBytes] 时抛出 [NetFrameOverflowException]，
  /// 由会话层断开连接（本次已切出的消息随连接终止一并丢弃）
  List<NetMessage> feed(List<int> data) {
    _buffer.addAll(data);

    final messages = <NetMessage>[];
    // 循环扫描缓冲区中所有完整行（一次喂入可能含多条消息）
    while (true) {
      final index = _buffer.indexOf(0x0A); // '\n'
      if (index < 0) break; // 剩余均为半行，留待下次喂入

      final lineBytes = _buffer.sublist(0, index);
      _buffer.removeRange(0, index + 1);

      final message = _decodeLine(lineBytes);
      if (message != null) messages.add(message);
    }

    // 扫描后剩余均为半行：超过上限说明对端在持续发送无换行字节流
    if (_buffer.length > _maxBufferBytes) {
      throw const NetFrameOverflowException();
    }
    return messages;
  }

  /// 解码单行字节为消息；空行与非 JSON 行返回 null（容错丢弃）
  NetMessage? _decodeLine(List<int> lineBytes) {
    if (lineBytes.isEmpty) return null;
    try {
      final json = jsonDecode(utf8.decode(lineBytes));
      if (json is! Map<String, dynamic>) return null;
      return NetMessage.fromJson(json);
    } on FormatException {
      return null;
    } on ArgumentError {
      // utf8.decode 遇到非法字节序列抛出，视为坏行丢弃
      return null;
    }
  }
}
