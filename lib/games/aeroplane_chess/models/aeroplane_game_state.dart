import 'package:horyx/shared/storage/archive_storage.dart';

/// 飞行棋玩家颜色
/// 枚举顺序即行动顺序（停机坪顺时针：绿→红→蓝→黄），开局绿方先掷
enum AeroplaneColor {
  green,
  red,
  blue,
  yellow;

  /// 中文展示名（摘要文案与 UI 展示的单一来源）
  String get label => switch (this) {
        AeroplaneColor.green => '绿',
        AeroplaneColor.red => '红',
        AeroplaneColor.blue => '蓝',
        AeroplaneColor.yellow => '黄',
      };

  /// 从持久化编码（枚举 name）还原；非法编码抛 [FormatException]
  static AeroplaneColor parse(String code) {
    for (final color in values) {
      if (color.name == code) return color;
    }
    throw FormatException('非法颜色编码: $code');
  }
}

/// 棋子所在区域
enum PlaneZone {
  hangar, // 停机坪机位
  ready, // 准备区（起飞后的待飞位，尚未踏上跑道）
  ring, // 外环
  runway, // 己方终点跑道
  goal; // 终点（己方跑道末格）

  /// 从持久化编码（枚举 name）还原；非法编码抛 [FormatException]
  static PlaneZone parse(String code) {
    for (final zone in values) {
      if (zone.name == code) return zone;
    }
    throw FormatException('非法区域编码: $code');
  }
}

/// 棋子位置 = 区域 + 线性索引（不可变值对象）
/// 索引含义按区域区分：
/// - [PlaneZone.hangar]：机位序号 0..3
/// - [PlaneZone.ready]：恒为 0（每方一个准备位）
/// - [PlaneZone.ring]：外环线性索引，上界由棋盘拓扑表约束，模型层只校验非负
/// - [PlaneZone.runway]：己方跑道格序号 0..4（末格即各方终点格，归 goal 表达）
/// - [PlaneZone.goal]：基地机位序号 0..3（已完成的飞机飞回基地以待飞位展示）
class PlanePosition {
  const PlanePosition._(this.zone, this.index);

  factory PlanePosition({required PlaneZone zone, required int index}) {
    final valid = switch (zone) {
      PlaneZone.hangar => index >= 0 && index <= 3,
      PlaneZone.ready => index == 0,
      PlaneZone.ring => index >= 0,
      PlaneZone.runway => index >= 0 && index <= 4,
      PlaneZone.goal => index >= 0 && index <= 3,
    };
    if (!valid) {
      throw ArgumentError('棋子位置索引越界: ${zone.name}#$index');
    }
    return PlanePosition._(zone, index);
  }

  final PlaneZone zone;

  final int index;

  @override
  bool operator ==(Object other) =>
      other is PlanePosition && other.zone == zone && other.index == index;

  @override
  int get hashCode => Object.hash(zone, index);

  @override
  String toString() => '${zone.name}#$index';
}

/// 参与者 = 颜色 + 玩家名；列表顺序即回合轮转顺序
class AeroplanePlayer {
  const AeroplanePlayer({required this.color, required this.name});

  final AeroplaneColor color;

  final String name;

  @override
  bool operator ==(Object other) =>
      other is AeroplanePlayer && other.color == color && other.name == name;

  @override
  int get hashCode => Object.hash(color, name);
}

/// 飞行棋对局状态（存档模型）
/// 不变式在构造时校验，非法输入抛 [ArgumentError]；
/// 反序列化入口 [fromJson] 统一抛 [FormatException]，由存档读取侧容错
class AeroplaneGameState implements GameArchiveSummary {
  AeroplaneGameState({
    required List<AeroplanePlayer> players,
    required Map<AeroplaneColor, List<PlanePosition>> planes,
    required this.currentPlayer,
    required this.consecutiveSixes,
    required this.gameOver,
    required this.winner,
    this.lastMoved,
    required this.savedAt,
  })  : players = List<AeroplanePlayer>.unmodifiable(players),
        planes = Map<AeroplaneColor, List<PlanePosition>>.unmodifiable({
          for (final entry in planes.entries)
            entry.key: List<PlanePosition>.unmodifiable(entry.value),
        }) {
    if (this.players.length < 2 || this.players.length > 4) {
      throw ArgumentError('玩家人数须为 2..4');
    }
    final colors = this.players.map((p) => p.color).toSet();
    if (colors.length != this.players.length) {
      throw ArgumentError('玩家颜色不能重复');
    }
    if (this.players.any((p) => p.name.isEmpty)) {
      throw ArgumentError('玩家名不能为空');
    }
    if (this.planes.length != this.players.length ||
        this.players.any((p) => this.planes[p.color]?.length != 4)) {
      throw ArgumentError('每个参与颜色须恰好有 4 枚棋子');
    }
    if (!colors.contains(currentPlayer)) {
      throw ArgumentError('当前行动方必须是参与玩家');
    }
    if (consecutiveSixes < 0) {
      throw ArgumentError('连 6 计数不能为负');
    }
    if (gameOver == (winner == null)) {
      throw ArgumentError('终局标记与获胜方须一致');
    }
    if (winner != null && !colors.contains(winner)) {
      throw ArgumentError('获胜方必须是参与玩家');
    }
    final moved = lastMoved;
    if (moved != null) {
      if (!colors.contains(moved.$1)) {
        throw ArgumentError('最后移动棋子必须是参与玩家');
      }
      if (moved.$2 < 0 || moved.$2 > 3) {
        throw ArgumentError('最后移动棋子编号越界: ${moved.$2}');
      }
    }
  }

  /// 参与玩家（2..4 人，列表顺序 = 回合轮转顺序）
  final List<AeroplanePlayer> players;

  /// 各参与颜色的棋子位置（每色 4 枚，列表顺序 = 棋子编号）
  final Map<AeroplaneColor, List<PlanePosition>> planes;

  /// 当前行动方
  final AeroplaneColor currentPlayer;

  /// 当前行动方的连 6 计数（掷出非 6 即清零）
  final int consecutiveSixes;

  /// 终局标记（已有玩家获胜）
  final bool gameOver;

  /// 获胜方（gameOver 为 true 时非空）
  final AeroplaneColor? winner;

  /// 最近一步移动的棋子（颜色, 编号），三 6 惩罚的目标；尚无移动记录时为 null
  final (AeroplaneColor, int)? lastMoved;

  /// 存档时间
  @override
  final DateTime savedAt;

  /// 存档进度摘要（设置页恢复卡片与存档管理页共用的单一文案来源）
  /// 进行中展示进度领先者（到达数最多，并列取轮转靠前）与当前行动方，
  /// 如「红 2/4 到达，轮到蓝方」；终局展示获胜方
  @override
  String get summary {
    if (gameOver) {
      return '${winner!.label}方胜利';
    }
    var leader = players.first;
    for (final p in players.skip(1)) {
      if (arrivedCount(p.color) > arrivedCount(leader.color)) {
        leader = p;
      }
    }
    return '${leader.color.label} ${arrivedCount(leader.color)}/4 到达，'
        '轮到${currentPlayer.label}方';
  }

  /// 数据格式版本号：字段结构变更时递增，便于后续读取旧档时迁移
  static const int version = 1;

  /// 指定颜色的棋子位置列表（恒 4 枚）
  List<PlanePosition> planesOf(AeroplaneColor color) => planes[color]!;

  /// 指定颜色已抵达终点的棋子数
  int arrivedCount(AeroplaneColor color) =>
      planesOf(color).where((p) => p.zone == PlaneZone.goal).length;

  Map<String, dynamic> toJson() => {
        'version': version,
        'players': [
          for (final p in players) [p.color.name, p.name],
        ],
        'planes': {
          for (final p in players)
            p.color.name: [
              for (final pos in planes[p.color]!) [pos.zone.name, pos.index],
            ],
        },
        'currentPlayer': currentPlayer.name,
        'consecutiveSixes': consecutiveSixes,
        'gameOver': gameOver,
        'winner': winner?.name,
        'lastMoved': switch (lastMoved) {
          null => null,
          (var color, var planeId) => [color.name, planeId],
        },
        'savedAt': savedAt.toIso8601String(),
      };

  /// 反序列化；数据缺失或格式不符时抛出 [FormatException]，由上层容错处理
  factory AeroplaneGameState.fromJson(Map<String, dynamic> json) {
    final rawPlayers = json['players'];
    if (rawPlayers is! List) {
      throw const FormatException('存档 players 字段无效');
    }
    final players = <AeroplanePlayer>[];
    for (final item in rawPlayers) {
      if (item is! List || item.length != 2) {
        throw const FormatException('存档 players 条目无效');
      }
      final code = item[0];
      final name = item[1];
      if (code is! String || name is! String) {
        throw const FormatException('存档 players 条目无效');
      }
      players.add(AeroplanePlayer(color: AeroplaneColor.parse(code), name: name));
    }

    final rawPlanes = json['planes'];
    if (rawPlanes is! Map<String, dynamic>) {
      throw const FormatException('存档 planes 字段无效');
    }
    final planes = <AeroplaneColor, List<PlanePosition>>{};
    for (final player in players) {
      final rawList = rawPlanes[player.color.name];
      if (rawList is! List) {
        throw const FormatException('存档 planes 条目无效');
      }
      final positions = <PlanePosition>[];
      for (final item in rawList) {
        if (item is! List || item.length != 2) {
          throw const FormatException('存档棋子位置条目无效');
        }
        final zoneCode = item[0];
        final index = item[1];
        if (zoneCode is! String || index is! int) {
          throw const FormatException('存档棋子位置条目无效');
        }
        try {
          positions.add(PlanePosition(zone: PlaneZone.parse(zoneCode), index: index));
        } on ArgumentError {
          throw const FormatException('存档棋子位置条目无效');
        }
      }
      planes[player.color] = positions;
    }

    final currentCode = json['currentPlayer'];
    if (currentCode is! String) {
      throw const FormatException('存档 currentPlayer 字段无效');
    }
    final sixes = json['consecutiveSixes'];
    if (sixes is! int || sixes < 0) {
      throw const FormatException('存档 consecutiveSixes 字段无效');
    }
    final gameOver = json['gameOver'];
    if (gameOver is! bool) {
      throw const FormatException('存档 gameOver 字段无效');
    }
    final rawWinner = json['winner'];
    AeroplaneColor? winner;
    if (rawWinner != null) {
      if (rawWinner is! String) {
        throw const FormatException('存档 winner 字段无效');
      }
      winner = AeroplaneColor.parse(rawWinner);
    }
    final rawLastMoved = json['lastMoved'];
    (AeroplaneColor, int)? lastMoved;
    if (rawLastMoved != null) {
      if (rawLastMoved is! List ||
          rawLastMoved.length != 2 ||
          rawLastMoved[0] is! String ||
          rawLastMoved[1] is! int) {
        throw const FormatException('存档 lastMoved 字段无效');
      }
      lastMoved = (
        AeroplaneColor.parse(rawLastMoved[0] as String),
        rawLastMoved[1] as int,
      );
    }
    final rawSavedAt = json['savedAt'];
    if (rawSavedAt is! String) {
      throw const FormatException('存档 savedAt 字段无效');
    }
    try {
      return AeroplaneGameState(
        players: players,
        planes: planes,
        currentPlayer: AeroplaneColor.parse(currentCode),
        consecutiveSixes: sixes,
        gameOver: gameOver,
        winner: winner,
        lastMoved: lastMoved,
        savedAt: DateTime.parse(rawSavedAt),
      );
    } on ArgumentError {
      throw const FormatException('存档数据字段冲突');
    }
  }
}
