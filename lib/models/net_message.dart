/// 局域网联机协议消息类型
/// 一期按单词PK多人对局定义；后续游戏联机（围棋等）在此扩展类型，
/// 复用同一套传输层（NDJSON 分帧 + TCP 会话）
enum NetMessageType {
  /// 握手：客户端加入时自报（携带协议版本与玩家昵称）
  hello,

  /// 加入结果：房主应答（成功时携带分配的座位号，失败时携带原因）
  joinResponse,

  /// 有玩家入座：房主广播（房间等待页实时刷新座位）
  playerJoined,

  /// 有玩家离开：房主广播
  playerLeft,

  /// 满员开赛：房主广播（携带人数与座位顺序）
  gameStart,

  /// 提交单词：客户端发给房主（仅轮到的玩家发送）
  wordSubmit,

  /// 单词校验结果：房主单独应答提交者（通过/拒绝及原因）
  wordResult,

  /// 单词生效：房主广播（全端同步入列并轮换回合）
  wordApplied,

  /// 心跳探测：定时发送
  ping,

  /// 心跳应答：收到 ping 必须回
  pong,

  /// 主动退出：正常关闭前发送，对端据此区分「主动离开」与「异常掉线」
  bye,

  /// 房间发现探测：客户端 UDP 广播（不经 TCP 会话，见 room_discovery.dart）
  discoveryRequest,

  /// 房间信息应答：房主收到探测后单播应答（携带游戏名、人数与 TCP 端口）
  discoveryResponse,
}

/// 局域网联机协议消息
/// 所有联机通信统一封装为本模型：类型 + 载荷键值对，
/// 序列化为单行 JSON 传输（NDJSON 协议，见 net_protocol.dart）
class NetMessage {
  const NetMessage({required this.type, this.payload = const {}});

  /// 消息类型
  final NetMessageType type;

  /// 类型专属载荷（字段由各消息类型自行约定，取值需做类型断言）
  final Map<String, dynamic> payload;

  /// 协议版本号：双端不一致时由房主拒绝连接，
  /// 避免 App 升级改协议后新老版本连上出现不可预期行为
  static const int protocolVersion = 1;

  /// 序列化为 JSON 映射（供编码器输出）
  Map<String, dynamic> toJson() => {
        'v': protocolVersion,
        'type': type.name,
        'payload': payload,
      };

  /// 反序列化；版本不符、类型未知、结构不符时抛出 [FormatException]，
  /// 由会话层统一容错（丢弃该条消息并断开，视为对端实现异常）
  factory NetMessage.fromJson(Map<String, dynamic> json) {
    final version = json['v'];
    if (version is! int || version != protocolVersion) {
      throw const FormatException('协议版本不符');
    }
    final typeName = json['type'];
    if (typeName is! String) {
      throw const FormatException('消息缺少 type 字段');
    }
    final type = NetMessageType.values.asNameMap()[typeName];
    if (type == null) {
      // 字符串插值非常量，不能使用 const 构造
      throw FormatException('未知消息类型: $typeName');
    }
    final payload = json['payload'];
    return NetMessage(
      type: type,
      payload: payload is Map<String, dynamic> ? payload : const {},
    );
  }

  /// 便捷构造：心跳探测
  const NetMessage.ping() : this(type: NetMessageType.ping);

  /// 便捷构造：心跳应答
  const NetMessage.pong() : this(type: NetMessageType.pong);

  /// 便捷构造：主动退出
  const NetMessage.bye() : this(type: NetMessageType.bye);
}
