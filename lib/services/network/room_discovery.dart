import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/net_message.dart';
import 'net_protocol.dart';
import 'room_host.dart';

/// 已发现的房间条目（客户端视角）
/// 数据来自房主的 UDP 应答，字段与 discoveryResponse 载荷一一对应
class DiscoveredRoom {
  DiscoveredRoom({
    required this.ip,
    required this.tcpPort,
    required this.gameName,
    required this.players,
    required this.capacity,
    required this.lastSeen,
  });

  /// 房主地址（应答包源地址）
  final String ip;

  /// 房主 TCP 监听端口（加入时连接用）
  final int tcpPort;

  /// 游戏名称（如「单词PK」）
  final String gameName;

  /// 当前人数（含房主）；可变字段，由发现器收到新应答时就地刷新
  int players;

  /// 总人数；可变字段（房主理论上不会改人数，保持可变与 players 一致处理）
  int capacity;

  /// 最近一次收到应答的时刻；超时未刷新则视为房间已关闭
  DateTime lastSeen;

  /// 是否满员
  bool get isFull => players >= capacity;

  /// 房间唯一键（同一设备一个房间，IP 即可区分）
  String get key => ip;
}

/// 局域网房间发现器（客户端）
/// 周期性向局域网广播 UDP 探测（discoveryRequest），
/// 收集房主的单播应答（discoveryResponse）并维护房间列表：
/// - 新应答刷新对应房间的 lastSeen 与人数
/// - 超过 [staleTimeout] 未再应答的房间视为已关闭，从列表移除
/// UDP 允许丢包，单个探测丢失由下一轮周期重试兜底
class RoomDiscovery extends ChangeNotifier {
  RoomDiscovery({
    this.probeInterval = const Duration(seconds: 2),
    this.staleTimeout = const Duration(seconds: 7),
    List<String>? broadcastTargets,
  }) : _extraTargets = broadcastTargets ?? const [];

  /// 探测周期
  final Duration probeInterval;

  /// 房间失联判定时长（约 3 个探测周期无应答即移除）
  final Duration staleTimeout;

  /// 额外探测目标（测试注入 127.0.0.1 做回环验证用）
  final List<String> _extraTargets;

  RawDatagramSocket? _socket;
  Timer? _probeTimer;

  /// 已发现房间：IP -> 条目
  final Map<String, DiscoveredRoom> _rooms = {};

  /// 当前房间列表（按最近活跃排序，最新在前）
  List<DiscoveredRoom> get rooms {
    final list = _rooms.values.toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return list;
  }

  /// 启动发现：绑定随机 UDP 端口并立即探测一次，随后按周期重复
  Future<void> start() async {
    final socket = await RawDatagramSocket.bind('0.0.0.0', 0);
    // Windows 等平台向广播地址发包必须显式开启，否则报权限错误(10013)
    socket.broadcastEnabled = true;
    _socket = socket;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      _onDatagram(datagram);
    });
    // 提前缓存本机 IP 用于推导定向广播地址（_probe 为同步方法不能 await）
    _lastKnownLocalIp = await _localIpv4();
    _probe();
    _probeTimer = Timer.periodic(probeInterval, (_) {
      _probe();
      _evictStale();
    });
  }

  /// 停止发现并清空列表（页面销毁时调用）
  void stop() {
    _probeTimer?.cancel();
    _probeTimer = null;
    _socket?.close();
    _socket = null;
    _rooms.clear();
    notifyListeners();
  }

  /// 发送一轮探测：同时广播有限广播地址与本网段定向广播，
  /// 后者对部分不转发 255.255.255.255 的路由器/AP 更稳
  void _probe() {
    final socket = _socket;
    if (socket == null) return;
    final data = NetProtocol.encode(
      const NetMessage(type: NetMessageType.discoveryRequest),
    );
    // 目标端口固定为房主的发现端口（见 RoomHost.discoveryPort）
    final targets = <String>{'255.255.255.255', ..._extraTargets};
    final localIp = _lastKnownLocalIp;
    if (localIp != null) {
      // 推导网段定向广播地址：192.168.124.3 -> 192.168.124.255
      final parts = localIp.split('.');
      if (parts.length == 4) {
        targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
      }
    }
    for (final target in targets) {
      try {
        socket.send(data, InternetAddress(target), RoomHost.discoveryPort);
      } catch (_) {
        // 个别目标发送失败（无该类地址的路由）不影响其余目标
      }
    }
  }

  /// 本机局域网 IP 缓存（推导定向广播地址用）
  /// 首次探测时获取一次即可，网络切换的极端场景由下轮探测的
  /// 有限广播目标兜底
  String? _lastKnownLocalIp;

  /// 处理应答包：合法 discoveryResponse 更新/新增房间条目
  void _onDatagram(Datagram datagram) {
    try {
      // 广播回环会让本机房间也被自己发现（源 IP 为本机局域网地址），
      // 自己已建房时再「加入」会占双座位，直接排除
      final sourceIp = datagram.address.address;
      if (sourceIp == _lastKnownLocalIp) return;

      final decoded = jsonDecode(utf8.decode(datagram.data));
      if (decoded is! Map<String, dynamic>) return;
      final message = NetMessage.fromJson(decoded);
      if (message.type != NetMessageType.discoveryResponse) return;

      final payload = message.payload;
      final tcpPort = payload['tcpPort'];
      final gameName = payload['gameName'];
      final players = payload['players'];
      final capacity = payload['capacity'];
      if (tcpPort is! int ||
          gameName is! String ||
          players is! int ||
          capacity is! int) {
        return;
      }

      final ip = sourceIp;
      final existing = _rooms[ip];
      if (existing != null) {
        // 刷新已有房间：人数可能变化（有人加入/退出）
        existing.lastSeen = DateTime.now();
        existing.players = players;
        existing.capacity = capacity;
      } else {
        _rooms[ip] = DiscoveredRoom(
          ip: ip,
          tcpPort: tcpPort,
          gameName: gameName,
          players: players,
          capacity: capacity,
          lastSeen: DateTime.now(),
        );
      }
      notifyListeners();
    } catch (_) {
      // 坏包/异版消息忽略
    }
  }

  /// 移除超时未应答的房间（房主已关房或断网）
  void _evictStale() {
    final now = DateTime.now();
    final staleKeys = _rooms.entries
        .where((e) => now.difference(e.value.lastSeen) > staleTimeout)
        .map((e) => e.key)
        .toList();
    if (staleKeys.isEmpty) return;
    staleKeys.forEach(_rooms.remove);
    notifyListeners();
  }

  /// 获取本机局域网 IPv4（推导定向广播地址用）；失败返回 null
  Future<String?> _localIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) return address.address;
        }
      }
    } catch (_) {
      // 列举网卡失败不影响发现（有限广播目标仍会发出）
    }
    return null;
  }
}
