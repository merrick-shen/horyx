import 'dart:math';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';

/// 加油站航线常量：起点/落点（外环线性索引）与被穿越的敌方跑道
class FlightRoute {
  const FlightRoute({
    required this.start,
    required this.landing,
    required this.crossedColor,
    required this.crossedRunwayIndex,
  });

  /// 起点格（己色格，恰好落在此格才可选择飞越）
  final int start;

  /// 落点格（己色格，落点可再接一次同色跳跃）
  final int landing;

  /// 航线穿越的敌方跑道归属色
  final AeroplaneColor crossedColor;

  /// 被穿越的敌方跑道格序号（0..5，0 为外端入口格）
  final int crossedRunwayIndex;
}

/// 棋盘拓扑常量表（以 docs/image.png 实物图逐格核对定稿）
///
/// 外环 52 格，索引按行进方向（顺时针）递增；颜色序列为
/// 红/蓝/黄/绿 四色循环（index % 4），同色格间隔恒 4。
/// 各色自起飞格沿外环行进 48 格到达己方跑道入口，再经 6 格跑道奔向中心终点。
/// 坐标以「格」为单位（y 轴向下），供棋盘渲染按比例缩放；
/// 外环坐标由第一象限 14 点表绕中心 90° 旋转生成（旋转同时完成颜色轮转）。
abstract final class AeroplaneBoard {
  /// 外环格数
  static const int ringSize = 52;

  /// 每色跑道格数
  static const int runwaySize = 6;

  /// 每色停机坪机位数
  static const int hangarSlots = 4;

  /// 画布中心（终点）坐标
  static const Point<double> goalCenter = Point(7, 7);

  /// 外环格颜色（行进序索引 mod 4：0 红 / 1 蓝 / 2 黄 / 3 绿）
  static AeroplaneColor ringColor(int index) {
    if (index < 0 || index >= ringSize) {
      throw ArgumentError('外环索引越界: $index');
    }
    return switch (index % 4) {
      0 => AeroplaneColor.red,
      1 => AeroplaneColor.blue,
      2 => AeroplaneColor.yellow,
      _ => AeroplaneColor.green,
    };
  }

  /// 各色起飞格（外环行进序索引）
  static const Map<AeroplaneColor, int> takeoffIndex = {
    AeroplaneColor.green: 43,
    AeroplaneColor.red: 4,
    AeroplaneColor.blue: 17,
    AeroplaneColor.yellow: 30,
  };

  /// 各色跑道入口（外环最后一格，再进一步进入己方跑道 0 号格）
  static const Map<AeroplaneColor, int> runwayEntryIndex = {
    AeroplaneColor.green: 39,
    AeroplaneColor.red: 0,
    AeroplaneColor.blue: 13,
    AeroplaneColor.yellow: 26,
  };

  /// 各色加油站航线
  static const Map<AeroplaneColor, FlightRoute> flightRoutes = {
    AeroplaneColor.green: FlightRoute(
      start: 7,
      landing: 19,
      crossedColor: AeroplaneColor.blue,
      crossedRunwayIndex: 2,
    ),
    AeroplaneColor.red: FlightRoute(
      start: 20,
      landing: 32,
      crossedColor: AeroplaneColor.yellow,
      crossedRunwayIndex: 2,
    ),
    AeroplaneColor.blue: FlightRoute(
      start: 33,
      landing: 45,
      crossedColor: AeroplaneColor.green,
      crossedRunwayIndex: 2,
    ),
    AeroplaneColor.yellow: FlightRoute(
      start: 46,
      landing: 6,
      crossedColor: AeroplaneColor.red,
      crossedRunwayIndex: 2,
    ),
  };

  /// 同色跳跃目标：行进方向下一个同色格（间隔恒 4）
  static int nextSameColor(int index) => (index + 4) % ringSize;

  // ---------------------------------------------------------------------------
  // 环格索引 ↔ 画布坐标
  // ---------------------------------------------------------------------------

  /// 第一象限 14 点表（行进序 0..13，含红方入口 W 至蓝方入口 R）；
  /// 其中 6/7 为对角分割格的两枚三角格中心
  static const List<Point<double>> _quadrantA = [
    Point(7, 0), // 0 红入口 W
    Point(8, 0),
    Point(9, 0),
    Point(10, 0), // 3 N
    Point(10, 1),
    Point(10, 2), // 5 P
    Point(10.5, 3), // 6 分割格三角 1
    Point(11, 3.5), // 7 分割格三角 2
    Point(12, 3.5),
    Point(13, 3.5),
    Point(14, 4), // 10 Q
    Point(14, 5),
    Point(14, 6),
    Point(14, 7), // 13 蓝入口 R
  ];

  /// 绕中心 (7,7) 顺时针旋转 90°
  static Point<double> _rotate(Point<double> p) =>
      Point(14 - p.y, p.x);

  /// 外环格中心坐标（格单位）
  static Point<double> ringCellCenter(int index) {
    if (index < 0 || index >= ringSize) {
      throw ArgumentError('外环索引越界: $index');
    }
    var p = _quadrantA[index % 13];
    for (var i = 0; i < index ~/ 13; i++) {
      p = _rotate(p);
    }
    return p;
  }

  /// 跑道格中心坐标（0 号格为外端入口格，向中心递增）
  static Point<double> runwayCellCenter(AeroplaneColor color, int index) {
    if (index < 0 || index >= runwaySize) {
      throw ArgumentError('跑道索引越界: $index');
    }
    return switch (color) {
      AeroplaneColor.red => Point(7, 1 + index.toDouble()),
      AeroplaneColor.blue => Point(13 - index.toDouble(), 7),
      AeroplaneColor.yellow => Point(7, 13 - index.toDouble()),
      AeroplaneColor.green => Point(1 + index.toDouble(), 7),
    };
  }

  /// 停机坪机位中心坐标
  static Point<double> hangarSlotCenter(AeroplaneColor color, int slot) {
    if (slot < 0 || slot >= hangarSlots) {
      throw ArgumentError('机位索引越界: $slot');
    }
    final base = switch (color) {
      AeroplaneColor.green => [2, 2],
      AeroplaneColor.red => [12, 2],
      AeroplaneColor.blue => [12, 12],
      AeroplaneColor.yellow => [2, 12],
    };
    return Point(
      (base[0] + (slot % 2) * 2).toDouble(),
      (base[1] + (slot ~/ 2) * 2).toDouble(),
    );
  }
}
