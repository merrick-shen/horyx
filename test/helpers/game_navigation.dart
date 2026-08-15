import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/widgets/game_card.dart';

/// 从主页点击游戏卡片进入指定游戏页
/// [index] 与主页游戏列表顺序一致：0=单词PK 1=五子棋 2=围棋 3=计分器
Future<void> openGame(WidgetTester tester, int index) async {
  await tester.tap(find.byType(GameCard).at(index));
  await tester.pumpAndSettle();
}

/// 进入单词PK游戏页（主页第一张卡片）
Future<void> openWordPk(WidgetTester tester) => openGame(tester, 0);

/// 进入五子棋游戏页（主页第二张卡片）
Future<void> openGomoku(WidgetTester tester) => openGame(tester, 1);

/// 进入计分器页面（主页第四张卡片）
Future<void> openScoreboard(WidgetTester tester) => openGame(tester, 3);
