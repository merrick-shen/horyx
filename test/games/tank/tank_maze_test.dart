import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/games/tank/models/tank_maze.dart';

void main() {
  group('TankMaze 迷宫生成', () {
    const cols = 10;
    const rows = 7;

    test('所有单元格相互连通（BFS 可达全部格子）', () {
      final maze = TankMaze.generate(cols: cols, rows: rows);
      final visited = <(int, int)>{};
      final queue = <(int, int)>[(0, 0)];
      visited.add((0, 0));
      while (queue.isNotEmpty) {
        final (col, row) = queue.removeAt(0);
        for (final (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
          final nx = col + dx;
          final ny = row + dy;
          if (nx < 0 || nx >= cols || ny < 0 || ny >= rows) continue;
          if (visited.contains((nx, ny))) continue;
          if (maze.hasWallBetween(col, row, dx, dy)) continue;
          visited.add((nx, ny));
          queue.add((nx, ny));
        }
      }
      expect(visited.length, cols * rows, reason: '存在不可达的单元格');
    });

    test('外边界墙完整保留', () {
      final maze = TankMaze.generate(cols: cols, rows: rows);
      for (var y = 0; y < rows; y++) {
        expect(maze.hasWallBetween(0, y, -1, 0), isTrue, reason: '左边界缺墙');
        expect(maze.hasWallBetween(cols - 1, y, 1, 0), isTrue, reason: '右边界缺墙');
      }
      for (var x = 0; x < cols; x++) {
        expect(maze.hasWallBetween(x, 0, 0, -1), isTrue, reason: '上边界缺墙');
        expect(maze.hasWallBetween(x, rows - 1, 0, 1), isTrue, reason: '下边界缺墙');
      }
    });

    test('是完美迷宫：墙数恰为 生成树规模（总墙数 - 单元格数 + 1）', () {
      final maze = TankMaze.generate(cols: cols, rows: rows);
      // 完美迷宫打通 单元格数-1 面墙，无多余环路
      final totalWalls = cols * (rows + 1) + rows * (cols + 1);
      final expected = totalWalls - (cols * rows - 1);
      expect(maze.walls.length, expected);
    });

    test('相同随机种子生成相同迷宫（联机同步预留下的确定性）', () {
      final a = TankMaze.generate(random: Random(42));
      final b = TankMaze.generate(random: Random(42));
      expect(a.walls, b.walls);
    });
  });
}
