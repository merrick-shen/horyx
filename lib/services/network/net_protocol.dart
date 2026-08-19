import 'dart:convert';

import '../../models/net_message.dart';

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

/// NDJSON 分帧解码器：把无边界的 TCP 字节流切成一行行 JSON 消息
/// TCP 是字节流协议，存在半包（一条消息分多次到达）与
/// 粘包（多条消息一次到达）问题，必须缓冲增量数据按 \n 切分
class NetFrameDecoder {
  /// 行缓冲：累积尚未以 \n 结尾的半行字节
  final List<int> _buffer = [];

  /// 喂入一段原始字节，返回本次切出的完整消息
  /// 解析失败的行（损坏 JSON、版本不符等）直接丢弃不断开连接：
  /// 单条坏消息不足以判定对端异常，宽容处理避免误伤
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
