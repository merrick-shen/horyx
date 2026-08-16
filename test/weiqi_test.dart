import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/widgets/primary_button.dart';

import 'helpers/test_app.dart';
import 'helpers/weiqi_actions.dart';

/// 围棋页面测试
/// 覆盖：规格选择、落子轮换、悔棋与虚手、提子/自杀/打劫规则、
/// 终局数子、退出确认与对局存档恢复
void main() {
  setUpTestEnv();

  testWidgets('围棋：规格选择与对局视图元素', (tester) async {
    await pumpApp(tester);
    await openWeiqi(tester);

    // 设置视图：三档规格可选
    expect(find.text('9×9'), findsOneWidget);
    expect(find.text('13×13'), findsOneWidget);
    expect(find.text('19×19'), findsOneWidget);

    // 切换 19 路标准盘后开始对局
    await tester.tap(find.text('19×19'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始对局'));
    await tester.pumpAndSettle();

    // 对局视图：黑先执子 + 双方提子面板 + 操作按钮
    expect(find.text('当前执子'), findsOneWidget);
    expect(find.text('黑方'), findsOneWidget);
    expect(find.text('黑方提子'), findsOneWidget);
    expect(find.text('白方提子'), findsOneWidget);
    expect(find.text('虚手'), findsOneWidget);
    expect(find.text('悔棋'), findsOneWidget);
  });

  testWidgets('围棋：落子轮换与悔棋回退', (tester) async {
    await pumpApp(tester);
    await startWeiqiGame(tester);

    // 黑方落子后轮到白方
    await placeWeiqiStone(tester, boardSize: 9, col: 4, row: 4);
    expect(find.text('白方'), findsOneWidget);

    // 悔棋：撤回黑子，执子回退为黑方
    await tester.tap(find.text('悔棋'));
    await tester.pumpAndSettle();
    expect(find.text('黑方'), findsOneWidget);

    // 无着手可悔时悔棋禁用（onPressed 置空，灰底不可点击）
    final undoButton = find.ancestor(
      of: find.text('悔棋'),
      matching: find.byType(PrimaryButton),
    );
    expect(tester.widget<PrimaryButton>(undoButton).onPressed, isNull);
  });

  testWidgets('围棋：虚手轮换与对局中退出确认', (tester) async {
    await pumpApp(tester);
    await startWeiqiGame(tester);

    // 虚手（停一手）：不落子仅轮换执子方
    await tester.tap(find.text('虚手'));
    await tester.pumpAndSettle();
    expect(find.text('白方'), findsOneWidget);

    // 虚手也记入着手序列，悔棋可回退执子方
    await tester.tap(find.text('悔棋'));
    await tester.pumpAndSettle();
    expect(find.text('黑方'), findsOneWidget);

    // 悔棋后无着手：返回不打扰，直接回到设置视图
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.text('开始对局'), findsOneWidget);
    expect(find.text('Horyx'), findsNothing);

    // 重新开局并虚一手（有进行中内容）：返回弹出三选项确认弹窗
    await tester.tap(find.text('开始对局'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('虚手'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.text('退出对局？'), findsOneWidget);

    // 取消：留在对局
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('当前执子'), findsOneWidget);

    // 不保存并退出：直接回主页
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不保存并退出'));
    await tester.pumpAndSettle();
    expect(find.text('Horyx'), findsOneWidget);
    expect(find.text('开始对局'), findsNothing);
  });

  testWidgets('围棋：提子生效并更新提子数', (tester) async {
    await pumpApp(tester);
    await startWeiqiGame(tester);

    // 角部提子：黑(1,0) 白(0,0) 黑(0,1) 后角上白子无气被提
    await placeWeiqiStone(tester, boardSize: 9, col: 1, row: 0);
    await placeWeiqiStone(tester, boardSize: 9, col: 0, row: 0);
    await placeWeiqiStone(tester, boardSize: 9, col: 0, row: 1);

    // 黑方提子数更新为 1
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('黑方提子'))).data,
      '1',
    );
  });

  testWidgets('围棋：自杀手禁止落子', (tester) async {
    await pumpApp(tester);
    await startWeiqiGame(tester);

    // 白先围住角点：白(1,0)、白(0,1) 后黑落 (0,0) 无气且提不到子
    await placeWeiqiStone(tester, boardSize: 9, col: 2, row: 2);
    await placeWeiqiStone(tester, boardSize: 9, col: 1, row: 0);
    await placeWeiqiStone(tester, boardSize: 9, col: 3, row: 3);
    await placeWeiqiStone(tester, boardSize: 9, col: 0, row: 1);

    // 黑点 (0,0)：自杀手 → 提示且不进入预选
    await tester.tapAt(weiqiCell(tester, 0, 0, 9));
    await tester.pumpAndSettle();
    expect(find.text('此处不能落子（自杀手）'), findsOneWidget);
    expect(find.text('下棋'), findsNothing);
  });

  testWidgets('围棋：打劫不能立即回提', (tester) async {
    await pumpApp(tester);
    await startWeiqiGame(tester);

    // 构造劫争：黑(1,0)(0,1)(1,2)(5,5) 白(2,0)(1,1)(3,1)(2,2)
    final sequence = [
      (1, 0), (2, 0), (0, 1), (1, 1), (1, 2), (3, 1), (5, 5), (2, 2),
    ];
    for (final (col, row) in sequence) {
      await placeWeiqiStone(tester, boardSize: 9, col: col, row: row);
    }

    // 黑提劫：黑(2,1) 提掉白(1,1)，黑方提子数为 1
    await placeWeiqiStone(tester, boardSize: 9, col: 2, row: 1);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('黑方提子'))).data,
      '1',
    );

    // 白立即回提 (1,1) 重现历史局面 → 打劫被拒
    await tester.tapAt(weiqiCell(tester, 1, 1, 9));
    await tester.pumpAndSettle();
    expect(find.text('打劫：不能立即回提'), findsOneWidget);
    expect(find.text('下棋'), findsNothing);
  });

  testWidgets('围棋：双虚手终局与数子结果', (tester) async {
    await pumpApp(tester);
    await startWeiqiGame(tester);

    // 首次虚手仅轮换执子方，不触发终局
    await tester.tap(find.text('虚手'));
    await tester.pumpAndSettle();
    expect(find.text('白方'), findsOneWidget);
    expect(find.text('对局结束'), findsNothing);

    // 第二次连续虚手 → 终局：空盘数子黑 0 白 0，贴 7.5 后白胜
    await tester.tap(find.text('虚手'));
    await tester.pumpAndSettle();
    expect(find.text('白方胜利！'), findsOneWidget);
    expect(find.textContaining('黑 0 子'), findsOneWidget);
    expect(find.textContaining('白 0 子'), findsOneWidget);

    // 点击弹窗内「再来一局」：清盘回到黑先执子
    await tester.tap(find.descendant(
      of: find.byType(Dialog),
      matching: find.text('再来一局'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('黑方'), findsOneWidget);
    expect(find.text('再来一局'), findsNothing);
  });

  testWidgets('围棋：保存退出与恢复对局', (tester) async {
    await pumpApp(tester);
    await startWeiqiGame(tester);

    // 黑方落一子后保存退出
    await placeWeiqiStone(tester, boardSize: 9, col: 4, row: 4);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存并退出'));
    await tester.pumpAndSettle();
    expect(find.text('Horyx'), findsOneWidget);

    // 重进：设置视图展示恢复入口与进度摘要
    await openWeiqi(tester);
    await tester.pumpAndSettle();
    expect(find.text('继续上次对局'), findsOneWidget);
    expect(find.text('9×9 对局 · 已下 1 手'), findsOneWidget);

    // 恢复对局：黑已下 1 手，轮到白方执子
    await tester.tap(find.text('继续上次对局'));
    await tester.pumpAndSettle();
    expect(find.text('白方'), findsOneWidget);

    // 恢复后可继续对弈：白方落子后轮黑
    await placeWeiqiStone(tester, boardSize: 9, col: 5, row: 5);
    expect(find.text('黑方'), findsOneWidget);
  });

  testWidgets('围棋：终局后存档随之失效', (tester) async {
    await pumpApp(tester);
    await startWeiqiGame(tester);

    // 造一个存档：黑白各落一子（数子 1:1，恢复后双虚手可判定胜负）
    await placeWeiqiStone(tester, boardSize: 9, col: 4, row: 4);
    await placeWeiqiStone(tester, boardSize: 9, col: 5, row: 5);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存并退出'));
    await tester.pumpAndSettle();

    // 重进并恢复对局：已下 2 手，轮到黑方
    await openWeiqi(tester);
    await tester.pumpAndSettle();
    expect(find.text('9×9 对局 · 已下 2 手'), findsOneWidget);
    await tester.tap(find.text('继续上次对局'));
    await tester.pumpAndSettle();
    expect(find.text('黑方'), findsOneWidget);

    // 双虚手终局：盘面黑 1 子白 1 子（空域互为公气不计），
    // 贴 7.5 后白胜 → 弹窗选择返回设置
    await tester.tap(find.text('虚手'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('虚手'));
    await tester.pumpAndSettle();
    expect(find.text('白方胜利！'), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byType(Dialog),
      matching: find.text('返回设置'),
    ));
    await tester.pumpAndSettle();

    // 设置阶段无进行中对局，直接退出页面
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();

    // 重进：存档已随终局清除，不再展示恢复入口
    await openWeiqi(tester);
    await tester.pumpAndSettle();
    expect(find.text('继续上次对局'), findsNothing);
    expect(find.text('开始对局'), findsOneWidget);
  });
}
