import 'dart:collection';
import 'dart:math';

/// 迷宫墙标识 (x, y, isVertical)：
/// - 竖墙（isVertical=true）位于单元格 (x-1, y) 与 (x, y) 之间，
///   x 取 0..cols（0 与 cols 为左右外边界）；
/// - 横墙（isVertical=false）位于单元格 (x, y-1) 与 (x, y) 之间，
///   y 取 0..rows（0 与 rows 为上下外边界）。
typedef MazeWall = (int, int, bool);

/// 坦克动荡对局迷宫：cols×rows 网格，墙存在于单元格边缘。
/// 采用递归回溯（随机深度优先）生成完美迷宫：全图连通、无环路，
/// 与原版树状迷宫风格一致；外边界墙永不打通。
class TankMaze {
  TankMaze._(this.cols, this.rows, this._walls);

  /// 生成一局随机迷宫
  factory TankMaze.generate({
    int cols = 10,
    int rows = 7,
    Random? random,
  }) {
    final rng = random ?? Random();

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

    return TankMaze._(cols, rows, walls);
  }

  /// 网格列数 / 行数
  final int cols;
  final int rows;

  /// 当前存在的墙（只读视图）
  final Set<MazeWall> _walls;
  Iterable<MazeWall> get walls => UnmodifiableSetView(_walls);

  /// 单元格 (col, row) 沿 (dx, dy) 方向的相邻格之间是否有墙
  /// （后续坦克/子弹的通行与反弹判定共用此入口）
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
