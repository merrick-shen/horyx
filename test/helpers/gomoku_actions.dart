import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/widgets/stone_board.dart';

import 'game_navigation.dart';

/// 进入五子棋并以默认 15 路盘开始对局
Future<void> startGomokuGame(WidgetTester tester) async {
  await openGomoku(tester);
  await tester.tap(find.text('开始对局'));
  await tester.pumpAndSettle();
}

/// 计算五子棋棋盘交叉点的屏幕坐标（用于 tapAt 模拟点击棋盘）
/// 棋盘结构：Container 内边距 8 + 画布区域，交叉点 = 边距(1格) + col*cell
Offset gomokuCell(WidgetTester tester, int col, int row) {
  final board = tester.renderObject(find.byType(StoneBoard)) as RenderBox;
  // 15 路棋盘（默认规格）：画布宽 = 组件宽 - 两侧内边距
  final paintWidth = board.size.width - 16;
  final cell = paintWidth / 16;
  final local = Offset(
    8 + cell * (col + 1),
    8 + cell * (row + 1),
  );
  return board.localToGlobal(local);
}

/// 在五子棋棋盘指定交叉点完成「点选 → 确认」完整落子
Future<void> placeGomokuStone(WidgetTester tester, int col, int row) async {
  await tester.tapAt(gomokuCell(tester, col, row));
  await tester.pumpAndSettle();
  await tester.tap(find.text('下棋'));
  await tester.pumpAndSettle();
}
