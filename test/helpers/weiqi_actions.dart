import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/widgets/stone_board.dart';

import 'game_navigation.dart';

/// 进入围棋页面（主页第三张卡片）
Future<void> openWeiqi(WidgetTester tester) => openGame(tester, 2);

/// 进入围棋并以指定规格开始对局；不传规格时保持默认 9 路
Future<void> startWeiqiGame(WidgetTester tester, {int? boardSize}) async {
  await openWeiqi(tester);
  if (boardSize != null) {
    await tester.tap(find.text('$boardSize×$boardSize'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('开始对局'));
  await tester.pumpAndSettle();
}

/// 计算围棋棋盘交叉点的屏幕坐标（boardSize 为当前对局路数）
/// 棋盘结构：Container 内边距 8 + 画布区域，交叉点 = 边距(1格) + col*cell
/// 与五子棋 helper 不同：路数由调用方传入（围棋支持 9/13/19 三档）
Offset weiqiCell(WidgetTester tester, int col, int row, int boardSize) {
  final board = tester.renderObject(find.byType(StoneBoard)) as RenderBox;
  final paintWidth = board.size.width - 16;
  final cell = paintWidth / (boardSize + 1);
  final local = Offset(
    8 + cell * (col + 1),
    8 + cell * (row + 1),
  );
  return board.localToGlobal(local);
}

/// 在围棋棋盘指定交叉点完成「点选 → 确认」完整落子
Future<void> placeWeiqiStone(
  WidgetTester tester, {
  required int boardSize,
  required int col,
  required int row,
}) async {
  await tester.tapAt(weiqiCell(tester, col, row, boardSize));
  await tester.pumpAndSettle();
  await tester.tap(find.text('下棋'));
  await tester.pumpAndSettle();
}
