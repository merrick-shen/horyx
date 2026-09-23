import 'dart:collection';
import 'dart:math';

/// 迷宫墙标识 (x, y, isVertical)：
/// - 竖墙（isVertical=true）位于单元格 (x-1, y) 与 (x, y) 之间，
///   x 取 0..cols（0 与 cols 为左右外边界）；
/// - 横墙（isVertical=false）位于单元格 (x, y-1) 与 (x, y) 之间，
///   y 取 0..rows（0 与 rows 为上下外边界）。
typedef MazeWall = (int, int, bool);

/// 坦克动荡对局迷宫：cols×rows 网格，墙存在于单元格边缘。
/// 采用递归回溯（随机深度优先）生成完美迷宫后，再做「编织」后处理：
/// 按概率为死胡同格随机打通额外内墙，引入环路
/// 完美迷宫（生成树）中任意两点间仅有一条路，双方出生点之间必然唯一路径，
/// 补环后出生点间存在多条可选路线，
/// 同时保留原版树状迷宫的走廊风格，外边界墙永不打通。
class TankMaze {
  TankMaze._(this.cols, this.rows, this.seed, this._walls);

  /// 生成一局随机迷宫
  ///
  /// [seed] 指定随机种子（联机同步：双端同种子生成同一迷宫）；
  /// 缺省时自生成并记录在 [seed] 字段（本地对局不影响随机性，
  /// 联机房主可读取该种子随回合开始消息广播）。
  /// [random] 为显式随机源（测试注入），优先于种子派生的随机源。
  /// [braidFactor] 为死胡同格被补环的概率（0 = 退化为完美迷宫；
  /// 越大越开阔多路），所有随机均走同一随机源，不影响种子同步。
  factory TankMaze.generate({
    int cols = 10,
    int rows = 7,
    Random? random,
    int? seed,
    double braidFactor = 0.8,
  }) {
    final actualSeed = seed ?? Random().nextInt(1 << 31);
    final rng = random ?? Random(actualSeed);

    // 初始所有墙（含外边界）全部存在
    final walls = <MazeWall>{
      for (var x = 0; x <= cols; x++)
        for (var y = 0; y < rows; y++)
          (x, y, true),
      for (var x = 0; x < cols; x++)
        for (var y = 0; y <= rows; y++)
          (x, y, false),
    };

    // 随机深度优先：从随机格出发，访问相邻未访问格时打通两格间的墙；
    // 无未访问邻居时回溯。最终恰好打通 单元格数-1 面墙（生成树）
    final visited = <(int, int)>{};
    final start = (rng.nextInt(cols), rng.nextInt(rows));
    final stack = <(int, int)>[start];
    visited.add(start);

    while (stack.isNotEmpty) {
      final (col, row) = stack.last;
      final passages = <((int, int), MazeWall)>[];
      for (final (dx, dy) in const [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
        final nx = col + dx;
        final ny = row + dy;
        if (nx < 0 || nx >= cols || ny < 0 || ny >= rows) continue;
        if (visited.contains((nx, ny))) continue;
        passages.add(((nx, ny), _wallBetween(col, row, dx, dy)));
      }
      if (passages.isEmpty) {
        stack.removeLast();
        continue;
      }
      final (next, wall) = passages[rng.nextInt(passages.length)];
      walls.remove(wall);
      visited.add(next);
      stack.add(next);
    }

    // 编织后处理：按行主序扫描，死胡同格（开放内墙方向恰为 1）以
    // [braidFactor] 概率随机打通一面现有内墙。打通只会增加开放方向，
    // 不会产生新死胡同；固定扫描顺序 + 同一随机源保证联机双端一致
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final walledDirs = <(int, int)>[];
        var openCount = 0;
        for (final (dx, dy) in const [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
          final nx = col + dx;
          final ny = row + dy;
          // 外边界墙永不参与打通，只统计内部相邻格
          if (nx < 0 || nx >= cols || ny < 0 || ny >= rows) continue;
          if (walls.contains(_wallBetween(col, row, dx, dy))) {
            walledDirs.add((dx, dy));
          } else {
            openCount++;
          }
        }
        if (openCount != 1) continue; // 非死胡同格
        if (rng.nextDouble() >= braidFactor) continue;
        final (dx, dy) = walledDirs[rng.nextInt(walledDirs.length)];
        walls.remove(_wallBetween(col, row, dx, dy));
      }
    }

    return TankMaze._(cols, rows, actualSeed, walls);
  }

  /// 网格列数 / 行数
  final int cols;
  final int rows;

  /// 本局迷宫的随机种子（联机同步用：随回合开始消息广播，
  /// 客户端以 `Random(seed)` 复现同一迷宫）
  final int seed;

  /// 当前存在的墙（只读视图）
  final Set<MazeWall> _walls;
  Iterable<MazeWall> get walls => UnmodifiableSetView(_walls);

  /// 单元格 (col, row) 沿 (dx, dy) 方向的相邻格之间是否有墙
  ///
  /// 仅供测试做迷宫连通性/边界墙校验使用；运行时坦克/子弹的通行与
  /// 反弹判定走几何碰撞（SAT），并不经过此入口
  bool hasWallBetween(int col, int row, int dx, int dy) =>
      _walls.contains(_wallBetween(col, row, dx, dy));

  /// 两相邻格之间的墙标识（方向为单步单位向量）
  static MazeWall _wallBetween(int col, int row, int dx, int dy) =>
      switch ((dx, dy)) {
        (0, -1) => (col, row, false), // 上方横墙
        (0, 1) => (col, row + 1, false), // 下方横墙
        (-1, 0) => (col, row, true), // 左侧竖墙
        (1, 0) => (col + 1, row, true), // 右侧竖墙
        _ => throw ArgumentError('方向必须为单步单位向量: ($dx, $dy)'),
      };
}
