import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_board.dart';
import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';

void main() {
  const colors = AeroplaneColor.values;

  group('格数与四色分布', () {
    test('外环 52 格，四色各 13 格', () {
      expect(AeroplaneBoard.ringSize, 52);
      for (final color in colors) {
        final count = List.generate(AeroplaneBoard.ringSize, (i) => i)
            .where((i) => AeroplaneBoard.ringColor(i) == color)
            .length;
        expect(count, 13);
      }
    });

    test('同色格间隔恒 4（nextSameColor 仍同色）', () {
      for (var i = 0; i < AeroplaneBoard.ringSize; i++) {
        expect(
          AeroplaneBoard.ringColor(AeroplaneBoard.nextSameColor(i)),
          AeroplaneBoard.ringColor(i),
        );
      }
    });

    test('跑道 6 格、停机坪 4 机位', () {
      expect(AeroplaneBoard.runwaySize, 6);
      expect(AeroplaneBoard.hangarSlots, 4);
    });

    test('外环索引越界抛错', () {
      expect(() => AeroplaneBoard.ringColor(-1), throwsArgumentError);
      expect(() => AeroplaneBoard.ringColor(52), throwsArgumentError);
    });
  });

  group('起飞格与跑道入口', () {
    test('起飞格与入口均为己色', () {
      for (final color in colors) {
        expect(
          AeroplaneBoard.ringColor(AeroplaneBoard.takeoffIndex[color]!),
          color,
        );
        expect(
          AeroplaneBoard.ringColor(AeroplaneBoard.runwayEntryIndex[color]!),
          color,
        );
      }
    });

    test('起飞格沿行进方向 48 格到达入口（外环绕行近一周）', () {
      for (final color in colors) {
        final distance = (AeroplaneBoard.runwayEntryIndex[color]! -
                AeroplaneBoard.takeoffIndex[color]!) %
            AeroplaneBoard.ringSize;
        expect(distance, 48);
      }
    });

    test('入口之后 3 格不经过的短弧内无己色格', () {
      for (final color in colors) {
        final entry = AeroplaneBoard.runwayEntryIndex[color]!;
        for (var k = 1; k <= 3; k++) {
          expect(
            AeroplaneBoard.ringColor((entry + k) % AeroplaneBoard.ringSize),
            isNot(color),
          );
        }
      }
    });
  });

  group('加油站航线', () {
    test('起落点均为己色，落点在起点前方 12 格', () {
      for (final color in colors) {
        final route = AeroplaneBoard.flightRoutes[color]!;
        expect(AeroplaneBoard.ringColor(route.start), color);
        expect(AeroplaneBoard.ringColor(route.landing), color);
        expect(
          route.landing,
          (route.start + 12) % AeroplaneBoard.ringSize,
        );
      }
    });

    test('起落点均在该色行进路径上（起飞格到入口之间）', () {
      for (final color in colors) {
        final route = AeroplaneBoard.flightRoutes[color]!;
        final takeoff = AeroplaneBoard.takeoffIndex[color]!;
        for (final cell in [route.start, route.landing]) {
          final offset = (cell - takeoff) % AeroplaneBoard.ringSize;
          expect(offset, inInclusiveRange(0, 48));
        }
      }
    });

    test('每色航线恰好穿越一条敌方跑道，四色互不遗漏', () {
      final crossed = <AeroplaneColor>{};
      for (final color in colors) {
        final route = AeroplaneBoard.flightRoutes[color]!;
        expect(route.crossedColor, isNot(color));
        expect(route.crossedRunwayIndex, inInclusiveRange(0, 5));
        crossed.add(route.crossedColor);
      }
      expect(crossed, colors.toSet());
    });
  });

  group('坐标换算', () {
    test('四个跑道入口位于四边中央', () {
      expect(AeroplaneBoard.ringCellCenter(0), const Point(0, -3.75));
      expect(AeroplaneBoard.ringCellCenter(13), const Point(3.75, 0));
      expect(AeroplaneBoard.ringCellCenter(26), const Point(0, 3.75));
      expect(AeroplaneBoard.ringCellCenter(39), const Point(-3.75, 0));
    });

    test('索引 +13 等于绕中心顺时针旋转 90°', () {
      Point<double> rotate(Point<double> p) => Point(-p.y, p.x);
      for (var i = 0; i < AeroplaneBoard.ringSize - 13; i++) {
        expect(
          AeroplaneBoard.ringCellCenter(i + 13),
          rotate(AeroplaneBoard.ringCellCenter(i)),
        );
      }
    });

    test('对角分割格的两枚三角中心重合', () {
      for (var q = 0; q < 4; q++) {
        expect(
          AeroplaneBoard.ringCellCenter(q * 13 + 6),
          AeroplaneBoard.ringCellCenter(q * 13 + 7),
        );
      }
    });

    test('外环相邻格中心衔接（距离不超过 1.5 格）', () {
      for (var i = 0; i < AeroplaneBoard.ringSize; i++) {
        final a = AeroplaneBoard.ringCellCenter(i);
        final b = AeroplaneBoard.ringCellCenter((i + 1) % AeroplaneBoard.ringSize);
        expect(a.distanceTo(b), lessThanOrEqualTo(1.5));
      }
    });

    test('入口与跑道 0 号格、跑道格间、跑道末格与终点的距离', () {
      for (final color in colors) {
        final entry = AeroplaneBoard.ringCellCenter(
          AeroplaneBoard.runwayEntryIndex[color]!,
        );
        expect(
          entry.distanceTo(AeroplaneBoard.runwayCellCenter(color, 0)),
          0.75,
        );
        for (var i = 0; i < AeroplaneBoard.runwaySize - 1; i++) {
          expect(
            AeroplaneBoard.runwayCellCenter(color, i).distanceTo(
              AeroplaneBoard.runwayCellCenter(color, i + 1),
            ),
            0.5,
          );
        }
        // 跑道末格即各方终点格
        expect(
          AeroplaneBoard.runwayCellCenter(color, AeroplaneBoard.runwaySize - 1),
          AeroplaneBoard.goalCellCenter(color),
        );
      }
    });

    test('跑道与机位坐标抽样', () {
      expect(AeroplaneBoard.runwayCellCenter(AeroplaneColor.red, 0),
          const Point(0, -3.0));
      expect(AeroplaneBoard.runwayCellCenter(AeroplaneColor.green, 5),
          const Point(-0.5, 0));
      final greenSlot0 = AeroplaneBoard.hangarSlotCenter(AeroplaneColor.green, 0);
      expect(greenSlot0.x, closeTo(-3.7, 1e-9));
      expect(greenSlot0.y, closeTo(-3.7, 1e-9));
      final blueSlot3 = AeroplaneBoard.hangarSlotCenter(AeroplaneColor.blue, 3);
      expect(blueSlot3.x, closeTo(2.85, 1e-9));
      expect(blueSlot3.y, closeTo(2.85, 1e-9));
      expect(AeroplaneBoard.boardCenter, const Point(0, 0));
    });

    test('全部坐标落在画布范围内', () {
      for (var i = 0; i < AeroplaneBoard.ringSize; i++) {
        final p = AeroplaneBoard.ringCellCenter(i);
        expect(p.x, inInclusiveRange(-4.25, 4.25));
        expect(p.y, inInclusiveRange(-4.25, 4.25));
      }
      for (final color in colors) {
        for (var i = 0; i < AeroplaneBoard.runwaySize; i++) {
          final p = AeroplaneBoard.runwayCellCenter(color, i);
          expect(p.x, inInclusiveRange(-4.25, 4.25));
          expect(p.y, inInclusiveRange(-4.25, 4.25));
        }
        for (var s = 0; s < AeroplaneBoard.hangarSlots; s++) {
          final p = AeroplaneBoard.hangarSlotCenter(color, s);
          expect(p.x, inInclusiveRange(-4.25, 4.25));
          expect(p.y, inInclusiveRange(-4.25, 4.25));
        }
      }
    });

    test('索引越界抛错', () {
      expect(() => AeroplaneBoard.ringCellCenter(52), throwsArgumentError);
      expect(
        () => AeroplaneBoard.runwayCellCenter(AeroplaneColor.red, 6),
        throwsArgumentError,
      );
      expect(
        () => AeroplaneBoard.hangarSlotCenter(AeroplaneColor.red, 4),
        throwsArgumentError,
      );
    });
  });
}
