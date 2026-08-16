import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/widgets/stone_board.dart';

import 'helpers/game_navigation.dart';
import 'helpers/gomoku_actions.dart';
import 'helpers/test_app.dart';

/// 五子棋功能测试
void main() {
  setUpTestEnv();

  testWidgets('五子棋：点击第二张卡片进入游戏页并选择规格', (tester) async {
    await pumpApp(tester);
    await openGomoku(tester);

    // 进入游戏页：顶栏展示「五子棋」，设置视图含规格选择
    expect(find.text('五子棋'), findsOneWidget);
    expect(find.text('棋盘规格'), findsOneWidget);
    expect(find.text('15×15'), findsOneWidget);
    expect(find.text('19×19'), findsOneWidget);
    expect(find.text('开始对局'), findsOneWidget);
    expect(find.text('更多'), findsNothing);
  });

  testWidgets('五子棋：开始对局切换到对局视图', (tester) async {
    await pumpApp(tester);
    await openGomoku(tester);

    // 选择 19 路大盘并开始对局
    await tester.tap(find.text('19×19'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始对局'));
    await tester.pumpAndSettle();

    // 对局视图：黑方先行提示、棋盘与悔棋按钮
    expect(find.text('当前执子'), findsOneWidget);
    expect(find.text('黑方'), findsOneWidget);
    expect(find.byType(StoneBoard), findsOneWidget);
    expect(find.text('悔棋'), findsOneWidget);
    // 无预选棋子时不显示取消/下棋按钮
    expect(find.text('取消'), findsNothing);
    expect(find.text('下棋'), findsNothing);
    // 设置视图已隐藏
    expect(find.text('棋盘规格'), findsNothing);
  });

  testWidgets('五子棋：点选棋盘出现预选与确认按钮，取消后消失', (tester) async {
    await pumpApp(tester);
    await startGomokuGame(tester);

    // 点击棋盘天元位置：预选棋子出现，确认按钮随之显示
    await tester.tapAt(gomokuCell(tester, 7, 7));
    await tester.pumpAndSettle();
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('下棋'), findsOneWidget);

    // 点击取消：预选消失，按钮隐藏，仍未落子（黑方执子）
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('取消'), findsNothing);
    expect(find.text('下棋'), findsNothing);
    expect(find.text('黑方'), findsOneWidget);
  });

  testWidgets('五子棋：确认落子轮换执子方并支持悔棋', (tester) async {
    await pumpApp(tester);
    await startGomokuGame(tester);

    // 黑方落子天元
    await placeGomokuStone(tester, 7, 7);
    expect(find.text('白方'), findsOneWidget);

    // 执子图标颜色随执子方变化：黑方执子显示黑子色，落子后为白子色
    final turnIcon = tester.widget<Icon>(find.byIcon(Icons.circle_rounded));
    expect(turnIcon.color, StoneBoard.whiteStone);

    // 白方点击已有棋子位置：不生成预选，确认按钮不出现
    await tester.tapAt(gomokuCell(tester, 7, 7));
    await tester.pumpAndSettle();
    expect(find.text('下棋'), findsNothing);

    await placeGomokuStone(tester, 8, 8);
    expect(find.text('黑方'), findsOneWidget);

    // 悔棋撤回白子：回到白方执子
    await tester.tap(find.text('悔棋'));
    await tester.pumpAndSettle();
    expect(find.text('白方'), findsOneWidget);

    // 再悔棋撤回黑子；无子可悔后按钮禁用，执子方不再变化
    await tester.tap(find.text('悔棋'));
    await tester.pumpAndSettle();
    expect(find.text('黑方'), findsOneWidget);
    // 空盘时图标恢复黑子色
    expect(
      tester.widget<Icon>(find.byIcon(Icons.circle_rounded)).color,
      StoneBoard.blackStone,
    );
    await tester.tap(find.text('悔棋'));
    await tester.pumpAndSettle();
    expect(find.text('黑方'), findsOneWidget);
  });

  testWidgets('五子棋：五连胜利弹窗、终局锁定与再来一局', (tester) async {
    await pumpApp(tester);
    await startGomokuGame(tester);

    // 黑方横向五连（白方在另一行干扰位落子）
    for (final (black, white) in [
      ((3, 7), (3, 8)),
      ((4, 7), (4, 8)),
      ((5, 7), (5, 8)),
      ((6, 7), (6, 8)),
    ]) {
      final (bc, br) = black;
      final (wc, wr) = white;
      await placeGomokuStone(tester, bc, br);
      await placeGomokuStone(tester, wc, wr);
    }
    // 黑方第 5 子连成五连
    await placeGomokuStone(tester, 7, 7);

    // 胜利弹窗：胜方标题与三个操作
    // （终局时底部也会出现「再来一局」，同名按钮需限定在弹窗内查找）
    final dialogRestart = find.descendant(
      of: find.byType(Dialog),
      matching: find.text('再来一局'),
    );
    expect(find.text('黑方胜利！'), findsOneWidget);
    expect(dialogRestart, findsOneWidget);
    expect(find.text('返回设置'), findsOneWidget);

    // 关闭弹窗查看棋盘：终局提示 + 棋盘锁定（点击不再生成预选）
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('对局结束'), findsOneWidget);
    expect(find.text('黑方胜利'), findsOneWidget);
    expect(find.text('悔棋'), findsNothing);
    await tester.tapAt(gomokuCell(tester, 10, 10));
    await tester.pumpAndSettle();
    expect(find.text('下棋'), findsNothing);

    // 底部再来一局：清盘回到黑方执子
    await tester.tap(find.text('再来一局'));
    await tester.pumpAndSettle();
    expect(find.text('当前执子'), findsOneWidget);
    expect(find.text('黑方'), findsOneWidget);
    expect(find.text('悔棋'), findsOneWidget);
  });

  testWidgets('五子棋：胜利弹窗返回设置视图', (tester) async {
    await pumpApp(tester);
    await startGomokuGame(tester);

    // 竖向五连（黑方 row 3..7，白方在旁列落子）
    for (final (black, white) in [
      ((7, 3), (8, 3)),
      ((7, 4), (8, 4)),
      ((7, 5), (8, 5)),
      ((7, 6), (8, 6)),
    ]) {
      final (bc, br) = black;
      final (wc, wr) = white;
      await placeGomokuStone(tester, bc, br);
      await placeGomokuStone(tester, wc, wr);
    }
    await placeGomokuStone(tester, 7, 7);

    expect(find.text('黑方胜利！'), findsOneWidget);

    // 选择返回设置：回到规格选择视图
    await tester.tap(find.text('返回设置'));
    await tester.pumpAndSettle();
    expect(find.text('棋盘规格'), findsOneWidget);
    expect(find.text('开始对局'), findsOneWidget);
  });

  testWidgets('五子棋：退出弹窗与保存恢复流程', (tester) async {
    await pumpApp(tester);
    await startGomokuGame(tester);

    // 黑白各落一子
    await placeGomokuStone(tester, 7, 7);
    await placeGomokuStone(tester, 8, 8);

    // 对局中点击顶栏返回：弹出三选项确认弹窗
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.text('退出对局？'), findsOneWidget);
    expect(find.text('保存并退出'), findsOneWidget);
    expect(find.text('不保存并退出'), findsOneWidget);

    // 取消：留在对局
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('当前执子'), findsOneWidget);

    // 再次返回并保存退出：回到主页
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存并退出'));
    await tester.pumpAndSettle();
    expect(find.text('Horyx'), findsOneWidget);
    expect(find.text('棋盘规格'), findsNothing);

    // 重新进入游戏页：展示恢复入口（含棋盘规格与手数）
    await openGomoku(tester);
    expect(find.text('继续上次对局'), findsOneWidget);
    expect(find.text('15×15 对局 · 已落子 2 手'), findsOneWidget);

    // 点击继续：恢复对局进度（2 手后轮到黑方，已落子处不可再选）
    await tester.tap(find.text('继续上次对局'));
    await tester.pumpAndSettle();
    expect(find.text('当前执子'), findsOneWidget);
    expect(find.text('黑方'), findsOneWidget);
    await tester.tapAt(gomokuCell(tester, 7, 7));
    await tester.pumpAndSettle();
    expect(find.text('下棋'), findsNothing);
  });

  testWidgets('五子棋：不保存并退出丢弃对局', (tester) async {
    await pumpApp(tester);
    await startGomokuGame(tester);

    // 落一子后选择「不保存并退出」
    await placeGomokuStone(tester, 7, 7);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不保存并退出'));
    await tester.pumpAndSettle();
    expect(find.text('Horyx'), findsOneWidget);

    // 重新进入：存档已清除，不再展示继续入口
    await openGomoku(tester);
    expect(find.text('继续上次对局'), findsNothing);
    expect(find.text('棋盘规格'), findsOneWidget);
  });

  testWidgets('五子棋：开局未落子返回直接回设置页', (tester) async {
    await pumpApp(tester);
    await startGomokuGame(tester);

    // 尚无落子：无进行中内容，返回不打扰，直接回到设置视图
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.text('棋盘规格'), findsOneWidget);
    expect(find.text('Horyx'), findsNothing);
  });
}
