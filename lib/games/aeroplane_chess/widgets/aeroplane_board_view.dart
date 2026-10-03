import 'dart:math';

import 'package:flutter/material.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_board.dart';
import 'package:horyx/games/aeroplane_chess/models/aeroplane_colors.dart';
import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';
import 'package:horyx/games/aeroplane_chess/widgets/aeroplane_plane.dart';
import 'package:horyx/shared/theme/app_theme.dart';

/// 绕中心顺时针旋转 90°，与拓扑表同一旋转
Point<double> _rotQuadrant(Point<double> p) => Point(-p.y, p.x);

List<Point<double>> _rotN(List<Point<double>> pts, int times) {
  var r = pts;
  for (var i = 0; i < times; i++) {
    r = [for (final p in r) _rotQuadrant(p)];
  }
  return r;
}

/// 飞行棋 - 棋盘视图：静态格子层 + 棋子层
/// 格子层按拓扑坐标表纯静态绘制（CustomPainter）：八角外环（顶/底行为
/// 半格竖条、转角列为半格横条、转角大三角与对角分割格衔接）、中央四色
/// 跑道（半格小格）与末端风车箭头、四角停机坪空机位、加油站短虚线箭头；
/// 棋子层按对局状态定位四区域（停机坪/外环/跑道/终点），同格多子横向
/// 错开；四色取自 [AeroplaneColors]，绘制层不写死色值；棋盘卡片圆角
/// 描边与其他游戏棋盘统一（Radii.card + 主题描边色）
class AeroplaneBoardView extends StatelessWidget {
  const AeroplaneBoardView({
    super.key,
    required this.planes,
    this.movable = const {},
    this.selected,
    this.movingOverride,
    this.onPlaneTap,
  });

  /// 各色棋子位置（每色 4 枚）
  final Map<AeroplaneColor, List<PlanePosition>> planes;

  /// 可动棋子（高亮 + 可点击）
  final Set<(AeroplaneColor, int)> movable;

  /// 选中的棋子（白描边）
  final (AeroplaneColor, int)? selected;

  /// 走子动画中的棋子位置覆盖（颜色, 编号, 格子坐标）：
  /// 动画期间该棋子按覆盖坐标渲染而非其对局状态位置
  final (AeroplaneColor, int, Point<double>)? movingOverride;

  /// 点击可动棋子回调
  final void Function(AeroplaneColor color, int planeId)? onPlaneTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: palette.stroke),
        ),
        // 裁切保证贴边绘制的棋盘内容不溢出圆角
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.control),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest.width;
              return Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _BoardPainter()),
                  ..._buildPieces(size),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 棋子层
  // ---------------------------------------------------------------------------

  /// 棋子直径占画布比例（0.42 格 / 画布 8.5 格，与机位圆盘比例一致）
  static const double _pieceRatio = 0.42 / (AeroplaneBoard.canvasExtent * 2);

  List<Widget> _buildPieces(double size) {
    final pieceSize = size * _pieceRatio;
    // 格子坐标 → 画布像素（与格子绘制层同一线性映射）。
    // 不能用 Align 定位：其 alignment 映射空间是「父尺寸 − 子尺寸」，
    // 离中心越远偏差越大（边缘约半个棋子宽），棋子会整体向中心收缩
    Offset pixelOf(Point<double> p) => Offset(
          (p.x + AeroplaneBoard.canvasExtent) /
              (AeroplaneBoard.canvasExtent * 2) *
              size,
          (p.y + AeroplaneBoard.canvasExtent) /
              (AeroplaneBoard.canvasExtent * 2) *
              size,
        );
    final coords = <(AeroplaneColor, int), Point<double>>{};
    for (final entry in planes.entries) {
      for (var i = 0; i < entry.value.length; i++) {
        var coord = _coordOf(entry.key, entry.value[i]);
        final override = movingOverride;
        if (override != null && override.$1 == entry.key && override.$2 == i) {
          coord = override.$3;
        }
        coords[(entry.key, i)] = coord;
      }
    }
    // 同格分组（坐标近似相同），组内横向错开保证叠子可见
    final groups = <String, List<(AeroplaneColor, int)>>{};
    for (final entry in coords.entries) {
      (groups[_cellKey(entry.value)] ??= []).add(entry.key);
    }
    final pieces = <Widget>[];
    for (final group in groups.values) {
      for (var i = 0; i < group.length; i++) {
        final key = group[i];
        final base = coords[key]!;
        final offset = (i - (group.length - 1) / 2) * 0.16;
        final center = pixelOf(Point(base.x + offset, base.y));
        final tap = onPlaneTap;
        pieces.add(
          Positioned(
            left: center.dx - pieceSize / 2,
            top: center.dy - pieceSize / 2,
            width: pieceSize,
            height: pieceSize,
            child: AeroplanePlane(
              color: key.$1,
              highlighted: movable.contains(key),
              selected: selected == key,
              onTap: movable.contains(key) && tap != null
                  ? () => tap(key.$1, key.$2)
                  : null,
            ),
          ),
        );
      }
    }
    return pieces;
  }

  /// 棋子位置 → 格子坐标
  static Point<double> _coordOf(AeroplaneColor color, PlanePosition pos) =>
      switch (pos.zone) {
        PlaneZone.hangar => AeroplaneBoard.hangarSlotCenter(color, pos.index),
        PlaneZone.ring => AeroplaneBoard.ringAnchor(pos.index),
        PlaneZone.runway => AeroplaneBoard.runwayCellCenter(color, pos.index),
        PlaneZone.goal => AeroplaneBoard.goalCenter,
      };

  /// 同格分组的近似坐标 key
  static String _cellKey(Point<double> p) =>
      '${p.x.toStringAsFixed(1)},${p.y.toStringAsFixed(1)}';
}

class _BoardPainter extends CustomPainter {
  /// 画布半宽（格），与拓扑表 canvasExtent 一致
  static const double _extent = AeroplaneBoard.canvasExtent;

  /// 颜色 → 象限旋转次数（红 0 / 蓝 1 / 黄 2 / 绿 3，与外环象限序一致）
  static const Map<AeroplaneColor, int> _quadrantOf = {
    AeroplaneColor.red: 0,
    AeroplaneColor.blue: 1,
    AeroplaneColor.yellow: 2,
    AeroplaneColor.green: 3,
  };

  /// 每格像素数（paint 时按画布尺寸计算）
  double _s = 1;

  Offset _pt(Point<double> p) =>
      Offset((p.x + _extent) * _s, (p.y + _extent) * _s);

  @override
  void paint(Canvas canvas, Size size) {
    _s = size.width / (_extent * 2);
    _drawHangars(canvas);
    // 飞行线画在路径格下层：穿格段被格子与圆点覆盖，仅外露段可见
    _drawFlightRoutes(canvas);
    _drawRing(canvas);
    _drawRunways(canvas);
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) => false;

  // ---------------------------------------------------------------------------
  // 停机坪
  // ---------------------------------------------------------------------------

  void _drawHangars(Canvas canvas) {
    for (final color in AeroplaneColor.values) {
      final c = AeroplaneColors.of(color);
      final slots = [
        for (var i = 0; i < AeroplaneBoard.hangarSlots; i++)
          AeroplaneBoard.hangarSlotCenter(color, i),
      ];
      // 基地块：外缘贴画布边（4.25），内缘紧贴路径转角三角（2.25）
      final first = slots.first;
      final xLo = first.x >= 0 ? 2.25 : -4.25;
      final xHi = first.x >= 0 ? 4.25 : -2.25;
      final yLo = first.y >= 0 ? 2.25 : -4.25;
      final yHi = first.y >= 0 ? 4.25 : -2.25;
      final block = Rect.fromLTRB(
        (xLo + _extent) * _s,
        (yLo + _extent) * _s,
        (xHi + _extent) * _s,
        (yHi + _extent) * _s,
      );
      canvas.drawRect(block, Paint()..color = c);
      for (final slot in slots) {
        // 空机位：半透明白圆盘（棋子由棋子层按对局状态渲染）
        canvas.drawCircle(
          _pt(slot),
          0.28 * _s,
          Paint()..color = AeroplaneColors.cellDot.withValues(alpha: 0.45),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 外环
  // ---------------------------------------------------------------------------

  void _drawRing(Canvas canvas) {
    for (var i = 0; i < AeroplaneBoard.ringSize; i++) {
      final q = i ~/ 13;
      final t = i % 13;
      final c = AeroplaneColors.of(AeroplaneBoard.ringColor(i));
      if (t == 6 || t == 7) {
        // 对角分割格：两枚三角与白点（内心，距三边等距）随象限旋转
        final local = t == 6
            ? const [Point(1.25, -2.25), Point(2.25, -2.25), Point(1.25, -1.25)]
            : const [Point(2.25, -2.25), Point(2.25, -1.25), Point(1.25, -1.25)];
        final pts = _rotN(local, q);
        final path = _pathOf(pts);
        canvas.drawPath(path, Paint()..color = c);
        canvas.save();
        canvas.clipPath(path);
        _dot(canvas, AeroplaneBoard.splitDotAt(i), 0.21);
        canvas.restore();
      } else if (_cornerTriangles.containsKey(i)) {
        // 转角大三角：按参考图逐格核对，朝向不满足旋转对称
        final path = _pathOf(_cornerTriangles[i]!);
        canvas.drawPath(path, Paint()..color = c);
        canvas.save();
        canvas.clipPath(path);
        _dot(canvas, AeroplaneBoard.cornerDots[i]!, 0.21);
        canvas.restore();
      } else {
        final center = AeroplaneBoard.ringCellCenter(i);
        canvas.drawPath(
          _barPath(center, _barSize(t), q),
          Paint()..color = c,
        );
        _dot(canvas, center, 0.21);
      }
    }
  }

  /// 八个转角大三角顶点（绝对坐标，直角朝向按参考图逐格实测，
  /// 朝向不满足旋转对称）
  static const Map<int, List<Point<double>>> _cornerTriangles = {
    // N 顶行右：直角左下（左边贴入口行、底边贴行进格），缺右上
    3: [Point(1.25, -4.25), Point(1.25, -3.25), Point(2.25, -3.25)],
    // Q 右列上：直角左下，缺右上
    10: [Point(3.25, -2.25), Point(3.25, -1.25), Point(4.25, -1.25)],
    // S 右列下：直角左上，缺右下
    16: [Point(3.25, 1.25), Point(4.25, 1.25), Point(3.25, 2.25)],
    // B 底行右：直角左上，缺右下
    23: [Point(1.25, 3.25), Point(2.25, 3.25), Point(1.25, 4.25)],
    // E 底行左：直角右上，缺左下
    29: [Point(-2.25, 3.25), Point(-1.25, 3.25), Point(-1.25, 4.25)],
    // G 左列下：直角右上，缺左下
    36: [Point(-4.25, 1.25), Point(-3.25, 1.25), Point(-3.25, 2.25)],
    // I 左列上：直角右下，缺左上
    42: [Point(-3.25, -2.25), Point(-3.25, -1.25), Point(-4.25, -1.25)],
    // L 顶行左：直角右下，缺左上
    49: [Point(-1.25, -4.25), Point(-1.25, -3.25), Point(-2.25, -3.25)],
  };

  /// 长条方格尺寸（宽, 高，第一象限局部）：顶行竖条 0.5×1.0、
  /// 转角列横条 1.0×0.5（长边垂直于行进方向）
  static Point<double> _barSize(int t) =>
      (t == 4 || t == 5 || t == 11 || t == 12)
          ? const Point(1.0, 0.5)
          : const Point(0.5, 1.0);

  /// 长条方格路径：方格为轴对齐矩形，center 已是旋转后的绝对坐标，
  /// 仅尺寸随象限旋转在宽高间互换（半格长条旋转 90° 后横竖互换）
  Path _barPath(Point<double> center, Point<double> size, int q) {
    final s = q.isOdd ? Point(size.y, size.x) : size;
    return Path()
      ..addRect(
        Rect.fromLTRB(
          (center.x - s.x / 2 + _extent) * _s,
          (center.y - s.y / 2 + _extent) * _s,
          (center.x + s.x / 2 + _extent) * _s,
          (center.y + s.y / 2 + _extent) * _s,
        ),
      );
  }

  Path _pathOf(List<Point<double>> pts) => Path()
    ..addPolygon([for (final p in pts) _pt(p)], true);

  // ---------------------------------------------------------------------------
  // 跑道与中心风车箭头
  // ---------------------------------------------------------------------------

  /// 风车箭头轮廓（第一象限局部，尖指向中心）：头部为 45° 等腰直角
  /// 三角（高与半底宽同为 0.78，四个箭头头部拼合外轮廓恰为正方形），
  /// 四尖共点于棋盘中心，杆半宽 0.25 与跑道格同宽、延伸至跑道外端
  static const List<Point<double>> _arrowPoints = [
    Point(0, 0),
    Point(0.78, -0.78),
    Point(0.25, -0.78),
    Point(0.25, -3.25),
    Point(-0.25, -3.25),
    Point(-0.25, -0.78),
    Point(-0.78, -0.78),
  ];

  void _drawRunways(Canvas canvas) {
    for (final color in AeroplaneColor.values) {
      final c = AeroplaneColors.of(color);
      for (var i = 0; i < AeroplaneBoard.runwaySize; i++) {
        final p = AeroplaneBoard.runwayCellCenter(color, i);
        canvas.drawRect(
          Rect.fromLTRB(
            (p.x - 0.25 + _extent) * _s,
            (p.y - 0.25 + _extent) * _s,
            (p.x + 0.25 + _extent) * _s,
            (p.y + 0.25 + _extent) * _s,
          ),
          Paint()..color = c,
        );
      }
    }
    // 中心风车箭头按序绘制形成旋转叠压
    for (final color in AeroplaneColor.values) {
      final arrow = _rotN(_arrowPoints, _quadrantOf[color]!);
      canvas.drawPath(
        _pathOf(arrow),
        Paint()..color = AeroplaneColors.of(color),
      );
    }
    // 跑道白点最后绘制（与路径圆点同大小），叠印在箭头之上
    for (final color in AeroplaneColor.values) {
      for (var i = 0; i < AeroplaneBoard.runwaySize; i++) {
        _dot(canvas, AeroplaneBoard.runwayCellCenter(color, i), 0.21);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 加油站航线
  // ---------------------------------------------------------------------------

  void _drawFlightRoutes(Canvas canvas) {
    for (final entry in AeroplaneBoard.flightRoutes.entries) {
      final c = AeroplaneColors.of(entry.key);
      final route = entry.value;
      // 飞行线两端对齐起/落点分割格上己色的圆点（而非格子几何中心）
      _dashedArrow(
        canvas,
        AeroplaneBoard.splitDotAt(route.start),
        AeroplaneBoard.splitDotAt(route.landing),
        c,
      );
    }
  }

  /// 加油站航线虚线：自起点己色分割格沿行/列中心线直行，飞越敌方
  /// 跑道（跑道块处断开）直达落点己色分割格
  void _dashedArrow(
    Canvas canvas,
    Point<double> from,
    Point<double> to,
    Color color,
  ) {
    final isHorizontal = from.y == to.y;
    final d = isHorizontal
        ? (to.x > from.x ? 1.0 : -1.0)
        : (to.y > from.y ? 1.0 : -1.0);
    double axisOf(Point<double> p) => isHorizontal ? p.x : p.y;
    Point<double> pointAt(double c) =>
        isHorizontal ? Point(c, from.y) : Point(from.x, c);
    Offset pt(Point<double> p) => _pt(p);

    // 起止端贴圆点边缘（圆点半径 0.21），飞越跑道块处留断口
    final startAxis = axisOf(from) + d * 0.21;
    final endAxis = axisOf(to) - d * 0.21;
    final lo = min(startAxis, endAxis);
    final hi = max(startAxis, endAxis);
    // 跑道块（半宽 0.25）附近留断口
    final segments = <List<double>>[
      [lo, -0.27],
      [0.27, hi],
    ];
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.07 * _s
      ..strokeCap = StrokeCap.round;
    for (final seg in segments) {
      final a = pt(pointAt(seg[0]));
      final b = pt(pointAt(seg[1]));
      final segDir = (b - a) / (b - a).distance;
      final total = (b - a).distance;
      var t = 0.0;
      while (t < total) {
        final segEnd = min(t + 0.15 * _s, total);
        canvas.drawLine(a + segDir * t, a + segDir * segEnd, paint);
        t = segEnd + 0.10 * _s;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 基础图元
  // ---------------------------------------------------------------------------

  /// 格上白色圆点
  void _dot(Canvas canvas, Point<double> center, double radiusUnits) {
    canvas.drawCircle(
      _pt(center),
      radiusUnits * _s,
      Paint()..color = AeroplaneColors.cellDot,
    );
  }
}
