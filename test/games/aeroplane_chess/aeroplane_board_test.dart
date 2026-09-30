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
    test('四个跑道入口位于四边中点', () {
      expect(AeroplaneBoard.ringCellCenter(0), const Point(7, 0));
      expect(AeroplaneBoard.ringCellCenter(13), const Point(14, 7));
      expect(AeroplaneBoard.ringCellCenter(26), const Point(7, 14));
      expect(AeroplaneBoard.ringCellCenter(39), const Point(0, 7));
    });

    test('索引 +13 等于绕中心顺时针旋转 90°', () {
      Point<double> rotate(Point<double> p) => Point(14 - p.y, p.x);
      for (var i = 0; i < AeroplaneBoard.ringSize - 13; i++) {
        expect(
          AeroplaneBoard.ringCellCenter(i + 13),
          rotate(AeroplaneBoard.ringCellCenter(i)),
        );
      }
    });

    test('外环相邻格中心互相衔接（距离在 0 与 1.5 格之间）', () {
      for (var i = 0; i < AeroplaneBoard.ringSize; i++) {
        final a = AeroplaneBoard.ringCellCenter(i);
        final b = AeroplaneBoard.ringCellCenter((i + 1) % AeroplaneBoard.ringSize);
        expect(a.distanceTo(b), greaterThan(0));
        expect(a.distanceTo(b), lessThanOrEqualTo(1.5));
      }
    });

    test('入口与跑道 0 号格、跑道末格与终点均相邻', () {
      for (final color in colors) {
        final entry = AeroplaneBoard.ringCellCenter(
          AeroplaneBoard.runwayEntryIndex[color]!,
        );
        expect(
          entry.distanceTo(AeroplaneBoard.runwayCellCenter(color, 0)),
          1,
        );
        for (var i = 0; i < AeroplaneBoard.runwaySize - 1; i++) {
          expect(
            AeroplaneBoard.runwayCellCenter(color, i).distanceTo(
              AeroplaneBoard.runwayCellCenter(color, i + 1),
            ),
            1,
          );
        }
        expect(
          AeroplaneBoard
              .runwayCellCenter(color, AeroplaneBoard.runwaySize - 1)
              .distanceTo(AeroplaneBoard.goalCenter),
          1,
        );
      }
    });

    test('跑道与机位坐标抽样', () {
      expect(AeroplaneBoard.runwayCellCenter(AeroplaneColor.red, 0),
          const Point(7, 1));
      expect(AeroplaneBoard.runwayCellCenter(AeroplaneColor.green, 5),
          const Point(6, 7));
      expect(AeroplaneBoard.hangarSlotCenter(AeroplaneColor.green, 0),
          const Point(2, 2));
      expect(AeroplaneBoard.hangarSlotCenter(AeroplaneColor.blue, 3),
          const Point(14, 14));
      expect(AeroplaneBoard.goalCenter, const Point(7, 7));
    });

    test('全部坐标落在 0..14 画布范围内', () {
      for (var i = 0; i < AeroplaneBoard.ringSize; i++) {
        final p = AeroplaneBoard.ringCellCenter(i);
        expect(p.x, inInclusiveRange(0, 14));
        expect(p.y, inInclusiveRange(0, 14));
      }
      for (final color in colors) {
        for (var i = 0; i < AeroplaneBoard.runwaySize; i++) {
          final p = AeroplaneBoard.runwayCellCenter(color, i);
          expect(p.x, inInclusiveRange(0, 14));
          expect(p.y, inInclusiveRange(0, 14));
        }
        for (var s = 0; s < AeroplaneBoard.hangarSlots; s++) {
          final p = AeroplaneBoard.hangarSlotCenter(color, s);
          expect(p.x, inInclusiveRange(0, 14));
          expect(p.y, inInclusiveRange(0, 14));
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
