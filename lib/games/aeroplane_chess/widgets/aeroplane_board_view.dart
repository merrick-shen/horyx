import 'dart:math';

import 'package:flutter/material.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_board.dart';
import 'package:horyx/games/aeroplane_chess/models/aeroplane_colors.dart';
import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';
import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/widgets/page_content.dart';

/// 飞行棋 - 静态棋盘层
/// 按拓扑坐标表纯静态绘制，不参与对局状态：八角外环（顶/底行为
/// 半格竖条、转角列为半格横条、转角大三角与对角分割格衔接）、
/// 中央四色跑道（半格小格）与末端风车箭头、四角停机坪机位、
/// 加油站短虚线箭头（指向被穿越的敌方跑道格）；四色取自
/// [AeroplaneColors]，绘制层不写死色值；棋盘卡片圆角描边与其他
/// 游戏棋盘统一（Radii.card + 主题描边色）
class AeroplaneBoardView extends StatelessWidget {
  const AeroplaneBoardView({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PageContent(
      // 棋盘贴区域顶部而非垂直居中：对局页棋盘区与骰子区等分剩余
      // 空间，居中会在棋盘上方留出大片空白、把骰子压向页面底部
      child: Align(
        alignment: Alignment.topCenter,
        child: AspectRatio(
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
              child: CustomPaint(painter: _BoardPainter()),
            ),
          ),
        ),
      ),
    );
  }
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

  /// 绕中心顺时针旋转 90°，与拓扑表同一旋转
  static Point<double> _rot(Point<double> p) => Point(-p.y, p.x);

  static List<Point<double>> _rotN(List<Point<double>> pts, int times) {
    var r = pts;
    for (var i = 0; i < times; i++) {
      r = [for (final p in r) _rot(p)];
    }
    return r;
  }

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
        // 停机位：半透明白圆盘（叠在基地色上），比棋子大一点
        canvas.drawCircle(
          _pt(slot),
          0.28 * _s,
          Paint()..color = AeroplaneColors.cellDot.withValues(alpha: 0.45),
        );
        // 棋子：主色圈 + 纯白内圆 + 主色飞机（与路径圆点同大）
        canvas.drawCircle(
          _pt(slot),
          0.21 * _s,
          Paint()..color = c,
        );
        canvas.drawCircle(
          _pt(slot),
          0.16 * _s,
          Paint()..color = Colors.white,
        );
        _drawPlane(canvas, slot, 0.23, c);
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
        _dot(canvas, _splitDotAt(i), 0.21);
        canvas.restore();
      } else if (_cornerTriangles.containsKey(i)) {
        // 转角大三角：按参考图逐格核对，朝向不满足旋转对称
        final path = _pathOf(_cornerTriangles[i]!);
        canvas.drawPath(path, Paint()..color = c);
        canvas.save();
        canvas.clipPath(path);
        _dot(canvas, _cornerDots[i]!, 0.21);
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

  /// 转角大三角白点：各三角形内心（内切圆圆心，距三条边等距 0.293 格，
  /// 即由直角顶点向格中心内缩），白点完整不裁
  static const Map<int, Point<double>> _cornerDots = {
    3: Point(1.54, -3.54),
    10: Point(3.54, -1.54),
    16: Point(3.54, 1.54),
    23: Point(1.54, 3.54),
    29: Point(-1.54, 3.54),
    36: Point(-3.54, 1.54),
    42: Point(-3.54, -1.54),
    49: Point(-1.54, -3.54),
  };

  /// 分割格两枚白点（第一象限局部：t6 左上半 / t7 右下半，随象限旋转）
  static const List<Point<double>> _splitDots = [
    Point(1.54, -1.96),
    Point(1.96, -1.54),
  ];

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
      canvas.drawPath(_pathOf(arrow), Paint()..color = AeroplaneColors.of(color));
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
        _splitDotAt(route.start),
        _splitDotAt(route.landing),
        c,
      );
    }
  }

  /// 分割格白点坐标：index 为外环行进序（t 必为 6 或 7），
  /// 第一象限局部白点按象限旋转得绝对坐标
  Point<double> _splitDotAt(int index) =>
      _rotN([_splitDots[index % 13 - 6]], index ~/ 13).first;

  /// 加油站航线虚线：自起点己色分割格沿行/列中心线直行，飞越敌方
  /// 跑道（跑道块处断开）直达落点己色分割格
  void _dashedArrow(
    Canvas canvas,
    Point<double> from,
    Point<double> to,
    Color color,
  ) {
    final isHorizontal = from.y == to.y;
    final d = isHorizontal ? (to.x > from.x ? 1.0 : -1.0) : (to.y > from.y ? 1.0 : -1.0);
    double axisOf(Point<double> p) => isHorizontal ? p.x : p.y;
    Point<double> pointAt(double c) => isHorizontal ? Point(c, from.y) : Point(from.x, c);
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

  /// 飞机标识（Material 图标字形，居中绘制）
  void _drawPlane(
    Canvas canvas,
    Point<double> center,
    double units,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.flight_takeoff_rounded.codePoint),
        style: TextStyle(
          fontFamily: Icons.flight_takeoff_rounded.fontFamily,
          fontSize: units * _s,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      _pt(center) - Offset(painter.width / 2, painter.height / 2),
    );
  }
}
