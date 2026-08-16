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
}
