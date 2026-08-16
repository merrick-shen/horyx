import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/widgets/primary_button.dart';

import 'helpers/test_app.dart';
import 'helpers/weiqi_actions.dart';

/// 围棋页面测试
/// 当前阶段为静态 UI 骨架：规格选择、基础落子轮换、悔棋与虚手、退出确认
/// 规则逻辑（提子/打劫/终局数子）接入后在此扩展对应用例
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

  testWidgets('围棋：虚手轮换与对局中直接退出', (tester) async {
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

    // 对局中点返回：直接返回主页（退出确认弹窗随存档功能后续引入）
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
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
}
