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
/// 坐标为以棋盘中心为原点、大格为单位的理想化模型（y 轴向下），
/// 供棋盘渲染按比例缩放：外环为八角环——四条正交边中心线半径 3.75，
/// 方格是长边垂直于行进方向的半格长条，转角由转角大三角与对角分割格
/// 衔接；外环坐标由第一象限 13 点表绕中心 90° 旋转生成（旋转同时完成
/// 颜色轮转）。
abstract final class AeroplaneBoard {
  /// 外环格数
  static const int ringSize = 52;

  /// 每色跑道格数
  static const int runwaySize = 6;

  /// 每色停机坪机位数
  static const int hangarSlots = 4;

  /// 画布中心（终点）坐标
  static const Point<double> goalCenter = Point(0, 0);

  /// 画布半宽（格）：外环格外缘与停机坪块外缘平齐于 ±4.25，
  /// 即画布边缘（棋盘内容铺满画布，无额外留白）
  static const double canvasExtent = 4.25;

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

  /// 第一象限（右上）行进序 0..12 中心点表：0 为红方入口（顶行中央），
  /// 6/7 为同一对角分割格的两枚三角中心；其余象限绕中心顺时针旋转生成
  static const List<Point<double>> _quadrant = [
    Point(0, -3.75), // 0 入口
    Point(0.5, -3.75),
    Point(1.0, -3.75),
    Point(1.75, -3.75), // 3 转角三角
    Point(1.75, -3.0),
    Point(1.75, -2.5),
    Point(1.75, -1.75), // 6 分割格
    Point(1.75, -1.75), // 7 分割格（同格另一三角）
    Point(2.5, -1.75),
    Point(3.0, -1.75),
    Point(3.75, -1.75), // 10 转角三角
    Point(3.75, -1.0),
    Point(3.75, -0.5),
  ];

  /// 绕中心顺时针旋转 90°（y 轴向下）
  static Point<double> _rotate(Point<double> p) => Point(-p.y, p.x);

  /// 外环格中心坐标（格单位）
  static Point<double> ringCellCenter(int index) {
    if (index < 0 || index >= ringSize) {
      throw ArgumentError('外环索引越界: $index');
    }
    var p = _quadrant[index % 13];
    for (var i = 0; i < index ~/ 13; i++) {
      p = _rotate(p);
    }
    return p;
  }

  /// 跑道格中心坐标（0 号格为外端入口格，向中心以半格步长递增）
  static Point<double> runwayCellCenter(AeroplaneColor color, int index) {
    if (index < 0 || index >= runwaySize) {
      throw ArgumentError('跑道索引越界: $index');
    }
    final d = 3.0 - 0.5 * index;
    return switch (color) {
      AeroplaneColor.red => Point(0, -d),
      AeroplaneColor.blue => Point(d, 0),
      AeroplaneColor.yellow => Point(0, d),
      AeroplaneColor.green => Point(-d, 0),
    };
  }

  /// 停机坪机位中心坐标（2×2 布局，slot 0 靠外角，间距 0.85 格；
  /// base ±3.7 使机位外缘 3.7+0.55 与外环格外缘 ±4.25 平齐）
  static Point<double> hangarSlotCenter(AeroplaneColor color, int slot) {
    if (slot < 0 || slot >= hangarSlots) {
      throw ArgumentError('机位索引越界: $slot');
    }
    final base = switch (color) {
      AeroplaneColor.green => [-3.7, -3.7, 1.0, 1.0],
      AeroplaneColor.red => [3.7, -3.7, -1.0, 1.0],
      AeroplaneColor.blue => [3.7, 3.7, -1.0, -1.0],
      AeroplaneColor.yellow => [-3.7, 3.7, 1.0, -1.0],
    };
    return Point(
      base[0] + (slot % 2) * 0.85 * base[2],
      base[1] + (slot ~/ 2) * 0.85 * base[3],
    );
  }
}
