import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/game_navigation.dart';
import 'helpers/scoreboard_actions.dart';
import 'helpers/test_app.dart';

/// 计分器功能测试
void main() {
  setUpTestEnv();

  testWidgets('计分器：比分设置与计分板视图切换', (tester) async {
    await pumpApp(tester);
    await openScoreboard(tester);

    // 顶栏标题与三个输入框预填默认值：局数 3 / 胜利分 21 / 分差 2
    expect(find.text('计分器'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('21'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    // 修改赛制为 5 局并开始计分 → 横屏计分板：无顶栏（无返回箭头），红蓝双方展示
    // （已位于设置页，直接输入后开始，不再经过 startScoreboard 的主页入口）
    await tester.enterText(find.byKey(const Key('bestOfInput')), '5');
    await tester.pumpAndSettle();
    await tapStartScoring(tester);

    expect(find.text('红方'), findsOneWidget);
    expect(find.text('蓝方'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
    // 中央局分牌展示所选赛制与大比分标签
    expect(find.text('BO5'), findsOneWidget);
    expect(find.text('大比分'), findsOneWidget);
    expect(find.text('第 1 局'), findsOneWidget);

    // 退出计分 → 回到设置视图（顶栏返回箭头恢复）
    await tester.tap(find.text('退出计分'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    expect(find.text('赛制'), findsOneWidget);
  });

  testWidgets('计分器：数字输入生效、非法拦截与清空回退', (tester) async {
    await pumpApp(tester);
    await openScoreboard(tester);

    // 赛制输入 9 → 计分板展示 BO9
    // （已位于设置页，直接输入后开始）
    await tester.enterText(find.byKey(const Key('bestOfInput')), '9');
    await tester.pumpAndSettle();
    await tapStartScoring(tester);
    expect(find.text('BO9'), findsOneWidget);

    // 退出回设置：改为非法值 0（范围 1-31）→ 上次生效值 BO9 保持不变
    await tester.tap(find.text('退出计分'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bestOfInput')), '0');
    await tester.pumpAndSettle();
    await tapStartScoring(tester);
    expect(find.text('BO9'), findsOneWidget);

    // 清空输入 → 回退默认值 BO3（输入框保持空并显示提示文案）
    await tester.tap(find.text('退出计分'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bestOfInput')), '');
    await tester.pumpAndSettle();
    expect(find.text('输入局数'), findsOneWidget);
    await tapStartScoring(tester);
    expect(find.text('BO3'), findsOneWidget);

    // 胜利分与领先分差同样支持输入生效：改值后回退默认不报错
    await tester.tap(find.text('退出计分'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('winScoreInput')), '30');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('leadInput')), '3');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('leadInput')), '');
    await tester.pumpAndSettle();
    expect(find.text('输入分差'), findsOneWidget);
  });

  testWidgets('计分器：点击加分与局胜判定（含领先分差延续）', (tester) async {
    await pumpApp(tester);

    // 胜利分 3、领先分差 2（平分后需拉开 2 分）
    await startScoreboard(tester, winScore: '3', lead: '2');

    // 红 2 蓝 2 平分
    for (var i = 0; i < 2; i++) {
      await tapPanel(tester, true);
      await tapPanel(tester, false);
    }

    // 红 +1 → 3:2：到达胜利分但仅领先 1 分，本局不结束
    await tapPanel(tester, true);
    expect(find.text('红方赢下本局！'), findsNothing);
    expect(find.text('第 1 局'), findsOneWidget);

    // 红 +1 → 4:2：满足领先分差，赢下本局
    await tapPanel(tester, true);
    expect(find.text('红方赢下本局！'), findsOneWidget);
    expect(find.text('本局结束'), findsOneWidget);

    // 继续查看：留在本局结束画面，中央显示本局结束
    await tester.tap(find.text('继续查看'));
    await tester.pumpAndSettle();
    expect(find.text('本局结束'), findsOneWidget);

    // 点击计分区开始下一局：局分清零、局数推进、大比分 1:0
    await tapPanel(tester, true);
    expect(find.text('第 2 局'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(3));
  });

  testWidgets('计分器：整场胜负判定与再来一场', (tester) async {
    await pumpApp(tester);

    // 胜利分 3、领先分差 0（到分即胜），BO3 默认
    await startScoreboard(tester, winScore: '3', lead: '0');

    // 红方连下两局（BO3 需 2 胜）赢得整场
    for (var game = 0; game < 2; game++) {
      await tapPanel(tester, true, 3);
      if (game == 0) {
        // 第一局：局胜弹窗 → 下一局
        expect(find.text('红方赢下本局！'), findsOneWidget);
        await tester.tap(find.text('下一局'));
        await tester.pumpAndSettle();
      }
    }

    // 第二局结束即整场胜利：场胜弹窗，中央显示比赛结束
    expect(find.text('红方获得胜利！'), findsOneWidget);
    expect(find.text('比赛结束'), findsOneWidget);

    // 再来一场：比分与局数全部重置
    await tester.tap(find.text('再来一场'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 局'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(4));
  });

  testWidgets('计分器：撤销恢复上一次比分（含局胜回退）', (tester) async {
    await pumpApp(tester);

    await startScoreboard(tester, winScore: '3', lead: '0');

    // 红蓝各得 1 分 → 撤销 → 蓝方分数回退
    await tapPanel(tester, true);
    await tapPanel(tester, false);
    expect(find.text('1'), findsNWidgets(2));

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);

    // 红方赢下本局后继续查看，撤销回退局胜状态
    await tapPanel(tester, true, 2);
    expect(find.text('红方赢下本局！'), findsOneWidget);
    await tester.tap(find.text('继续查看'));
    await tester.pumpAndSettle();
    expect(find.text('本局结束'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    // 回到本局进行中：红 2 蓝 0，仍为第 1 局
    expect(find.text('第 1 局'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('本局结束'), findsNothing);
  });

  testWidgets('计分器：保存退出与恢复比分', (tester) async {
    await pumpApp(tester);

    await startScoreboard(tester, winScore: '3', lead: '0');

    // 红方得 2 分后退出的，弹出三选项确认
    await tapPanel(tester, true, 2);

    await tester.tap(find.text('退出计分'));
    await tester.pumpAndSettle();
    expect(find.text('退出计分？'), findsOneWidget);

    // 保存并退出 → 设置视图展示恢复入口（含当前比分摘要）
    await tester.tap(find.text('保存并退出'));
    await tester.pumpAndSettle();
    expect(find.text('继续上次计分'), findsOneWidget);
    expect(find.text('BO3 · 大比分 0:0 · 当前局 2:0'), findsOneWidget);

    // 恢复计分：横屏计分板还原比分与局数
    await tester.tap(find.text('继续上次计分'));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(find.text('第 1 局'), findsOneWidget);

    // 撤销栈随存档恢复：可撤销回 1 分
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);

    // 不保存并退出 → 存档清除，不再展示恢复入口
    await tester.tap(find.text('退出计分'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不保存并退出'));
    await tester.pumpAndSettle();
    expect(find.text('继续上次计分'), findsNothing);
    expect(find.text('赛制'), findsOneWidget);
  });

  testWidgets('计分器：整场终局后清除存档', (tester) async {
    await pumpApp(tester);
    await startScoreboard(tester, bestOf: '3', winScore: '2', lead: '0');

    // 造档：红方 1:0 后保存退出
    await tapPanel(tester, true, 1);
    await tester.tap(find.text('退出计分'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存并退出'));
    await tester.pumpAndSettle();
    expect(find.text('继续上次计分'), findsOneWidget);

    // 恢复并打完整场：红方连赢两局（2 分封顶制）
    await tester.tap(find.text('继续上次计分'));
    await tester.pumpAndSettle();
    await tapPanel(tester, true, 1); // 2:0 赢下第一局
    await tester.tap(find.text('下一局'));
    await tester.pumpAndSettle();
    await tapPanel(tester, true, 2); // 第二局 2:0，整场胜利
    await tester.pumpAndSettle();
    expect(find.text('红方获得胜利！'), findsOneWidget);

    // 取消弹窗留在终局画面，退出后不应再出现恢复入口（存档已随终局清除）
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出计分'));
    await tester.pumpAndSettle();
    expect(find.text('继续上次计分'), findsNothing);
    expect(find.text('赛制'), findsOneWidget);
  });
}
