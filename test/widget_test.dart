import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:horyx/main.dart';
import 'package:horyx/services/theme_storage.dart';
import 'package:horyx/services/word_validator.dart';
import 'package:horyx/theme/app_theme.dart';
import 'package:horyx/theme/theme_controller.dart';
import 'package:horyx/widgets/game_card.dart';
import 'package:horyx/widgets/stone_board.dart';

/// 在五子棋棋盘指定交叉点完成「点选 → 确认」完整落子
Future<void> placeGomokuStone(WidgetTester tester, int col, int row) async {
  await tester.tapAt(gomokuCell(tester, col, row));
  await tester.pumpAndSettle();
  await tester.tap(find.text('下棋'));
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

void main() {
  // 测试直接 pumpWidget 不经过 main()，需手动预加载单词词表
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await WordValidator.load();
  });

  // 每个测试使用独立的模拟本地存储
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('主页静态 UI 冒烟测试', (tester) async {
    await tester.pumpWidget(const MyApp());

    // 顶栏展示品牌名
    expect(find.text('Horyx'), findsOneWidget);
    // 游戏列表已渲染出占位卡片
    expect(find.text('开发中'), findsWidgets);
    // 底部导航栏包含首页与更多入口
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);
  });

  testWidgets('点击第一张卡片进入单词PK游戏页', (tester) async {
    await tester.pumpWidget(const MyApp());

    // 点击游戏列表第一张卡片
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();

    // 进入游戏页：顶栏展示「单词PK」且无底部导航栏
    expect(find.text('单词PK'), findsOneWidget);
    expect(find.text('更多'), findsNothing);
  });

  testWidgets('单词PK：人数设置与对局视图切换', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();

    // 设置视图：人数选择与开始按钮
    expect(find.text('参与人数'), findsOneWidget);
    expect(find.text('开始 PK'), findsOneWidget);

    // 选择 3 人并开始
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始 PK'));
    await tester.pumpAndSettle();

    // 对局视图：当前输入者、玩家序列、输入框
    expect(find.text('当前输入者'), findsOneWidget);
    expect(find.text('玩家 3'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    // 初始无单词，显示空状态（多行文案用包含匹配）
    expect(find.textContaining('还没有验证通过的单词'), findsOneWidget);
  });

  testWidgets('单词PK：提交流程（入列、轮换、重复与无效提示）', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始 PK'));
    await tester.pumpAndSettle();

    // 玩家1 输入有效单词：入列并轮换到玩家2
    await tester.enterText(find.byType(TextField), 'apple');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(find.text('apple'), findsOneWidget);
    expect(find.text('1 个'), findsOneWidget);

    // 玩家2 输入重复单词（忽略大小写）：提示且不入列、不轮换
    await tester.enterText(find.byType(TextField), 'Apple');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(find.text('单词已重复'), findsOneWidget);
    expect(find.text('1 个'), findsOneWidget);

    // 关闭提示后输入无效单词：提示不通过
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'qqqqzz');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(find.text('不是有效的英文单词'), findsOneWidget);
    expect(find.text('1 个'), findsOneWidget);

    // 关闭提示后输入非字母：提示不通过
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'app1e');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(find.text('单词只能由英文字母组成'), findsOneWidget);
  });

  testWidgets('单词PK：退出弹窗与保存恢复流程', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始 PK'));
    await tester.pumpAndSettle();

    // 玩家1 输入单词后轮换至玩家2
    await tester.enterText(find.byType(TextField), 'apple');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    // 对局中点击顶栏返回：弹出确认弹窗（三选项）
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.text('退出对局？'), findsOneWidget);
    expect(find.text('保存并退出'), findsOneWidget);
    expect(find.text('不保存并退出'), findsOneWidget);

    // 取消：留在对局
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('当前输入者'), findsOneWidget);

    // 再次返回并确认保存：退出游戏页回到主页
    // （主页第一张卡片名称也是「单词PK」，故以对局元素消失判断退出成功）
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存并退出'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('当前输入者'), findsNothing);
    expect(find.text('Horyx'), findsOneWidget);

    // 重新进入游戏页：展示「继续上次对局」入口
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();
    expect(find.text('继续上次对局'), findsOneWidget);

    // 点击继续：恢复对局进度（单词与当前输入者玩家2）
    await tester.tap(find.text('继续上次对局'));
    await tester.pumpAndSettle();
    expect(find.text('apple'), findsOneWidget);
    expect(find.text('当前输入者'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_rounded), findsOneWidget);
  });

  testWidgets('单词PK：不保存并退出丢弃对局', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始 PK'));
    await tester.pumpAndSettle();

    // 输入一个单词后选择「不保存并退出」
    await tester.enterText(find.byType(TextField), 'apple');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不保存并退出'));
    await tester.pumpAndSettle();
    expect(find.text('Horyx'), findsOneWidget);

    // 重新进入：存档已清除，不再展示继续入口
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();
    expect(find.text('继续上次对局'), findsNothing);
    expect(find.text('参与人数'), findsOneWidget);
  });

  testWidgets('单词PK：错误提示未关闭时退出不残留到主页', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byType(GameCard).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始 PK'));
    await tester.pumpAndSettle();

    // 触发错误提示（重复单词）且不关闭
    await tester.enterText(find.byType(TextField), 'apple');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'apple');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(find.text('单词已重复'), findsOneWidget);

    // 提示未关闭时保存并退出：提示不应残留到主页
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存并退出'));
    await tester.pumpAndSettle();
    expect(find.text('Horyx'), findsOneWidget);
    expect(find.text('单词已重复'), findsNothing);
    expect(find.text('知道了'), findsNothing);
  });

  testWidgets('点击第三张卡片进入围棋占位页', (tester) async {
    await tester.pumpWidget(const MyApp());

    // 点击游戏列表第三张卡片（围棋，玩法待开发）
    await tester.tap(find.byType(GameCard).at(2));
    await tester.pumpAndSettle();

    // 占位页：顶栏展示游戏名 + 开发中提示
    expect(find.byIcon(Icons.blur_on_rounded), findsWidgets);
    expect(find.text('功能开发中，敬请期待'), findsOneWidget);

    // 顶栏返回回主页
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Horyx'), findsOneWidget);
  });

  testWidgets('五子棋：点击第二张卡片进入游戏页并选择规格', (tester) async {
    await tester.pumpWidget(const MyApp());

    // 点击游戏列表第二张卡片（五子棋）
    await tester.tap(find.byType(GameCard).at(1));
    await tester.pumpAndSettle();

    // 进入游戏页：顶栏展示「五子棋」，设置视图含规格选择
    expect(find.text('五子棋'), findsOneWidget);
    expect(find.text('棋盘规格'), findsOneWidget);
    expect(find.text('15×15'), findsOneWidget);
    expect(find.text('19×19'), findsOneWidget);
    expect(find.text('开始对局'), findsOneWidget);
    expect(find.text('更多'), findsNothing);
  });

  testWidgets('五子棋：开始对局切换到对局视图', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byType(GameCard).at(1));
    await tester.pumpAndSettle();

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
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byType(GameCard).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始对局'));
    await tester.pumpAndSettle();

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
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byType(GameCard).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始对局'));
    await tester.pumpAndSettle();

    // 黑方落子天元
    await tester.tapAt(gomokuCell(tester, 7, 7));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下棋'));
    await tester.pumpAndSettle();
    expect(find.text('白方'), findsOneWidget);

    // 执子图标颜色随执子方变化：黑方执子显示黑子色，落子后为白子色
    final turnIcon = tester.widget<Icon>(find.byIcon(Icons.circle_rounded));
    expect(turnIcon.color, StoneBoard.whiteStone);

    // 白方点击已有棋子位置：不生成预选，确认按钮不出现
    await tester.tapAt(gomokuCell(tester, 7, 7));
    await tester.pumpAndSettle();
    expect(find.text('下棋'), findsNothing);

    await tester.tapAt(gomokuCell(tester, 8, 8));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下棋'));
    await tester.pumpAndSettle();
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
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byType(GameCard).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始对局'));
    await tester.pumpAndSettle();

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
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byType(GameCard).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始对局'));
    await tester.pumpAndSettle();

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
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byType(GameCard).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始对局'));
    await tester.pumpAndSettle();

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
    await tester.tap(find.byType(GameCard).at(1));
    await tester.pumpAndSettle();
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
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byType(GameCard).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始对局'));
    await tester.pumpAndSettle();

    // 落一子后选择「不保存并退出」
    await placeGomokuStone(tester, 7, 7);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不保存并退出'));
    await tester.pumpAndSettle();
    expect(find.text('Horyx'), findsOneWidget);

    // 重新进入：存档已清除，不再展示继续入口
    await tester.tap(find.byType(GameCard).at(1));
    await tester.pumpAndSettle();
    expect(find.text('继续上次对局'), findsNothing);
    expect(find.text('棋盘规格'), findsOneWidget);
  });

  testWidgets('计分器：比分设置与计分板视图切换', (tester) async {
    await tester.pumpWidget(const MyApp());

    // 点击第四张卡片（计分器）进入设置视图
    await tester.tap(find.byType(GameCard).at(3));
    await tester.pumpAndSettle();

    // 顶栏标题与三个输入框预填默认值：局数 3 / 胜利分 21 / 分差 2
    expect(find.text('计分器'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('21'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    // 修改赛制为 5 局
    await tester.enterText(find.byKey(const Key('bestOfInput')), '5');
    await tester.pumpAndSettle();

    // 开始计分 → 横屏计分板：无顶栏（无返回箭头），红蓝双方展示
    // 设置内容超出默认测试视口，先滚动到按钮可见
    await tester.ensureVisible(find.text('开始计分'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始计分'));
    await tester.pumpAndSettle();

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
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.byType(GameCard).at(3));
    await tester.pumpAndSettle();

    // 赛制输入 9 → 计分板展示 BO9
    await tester.enterText(find.byKey(const Key('bestOfInput')), '9');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('开始计分'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始计分'));
    await tester.pumpAndSettle();
    expect(find.text('BO9'), findsOneWidget);

    // 退出回设置：改为非法值 0（范围 1-31）→ 上次生效值 BO9 保持不变
    await tester.tap(find.text('退出计分'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bestOfInput')), '0');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('开始计分'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始计分'));
    await tester.pumpAndSettle();
    expect(find.text('BO9'), findsOneWidget);

    // 清空输入 → 回退默认值 BO3（输入框保持空并显示提示文案）
    await tester.tap(find.text('退出计分'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bestOfInput')), '');
    await tester.pumpAndSettle();
    expect(find.text('输入局数'), findsOneWidget);
    await tester.ensureVisible(find.text('开始计分'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始计分'));
    await tester.pumpAndSettle();
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

  testWidgets('设置页：主题入口跳转主题设置页', (tester) async {
    await tester.pumpWidget(const MyApp());

    // 切换到底部导航「更多」页
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();

    // 设置页展示主题设置入口
    expect(find.text('主题'), findsOneWidget);

    // 点击进入主题设置页：展示主题模式三选项，不再是占位页
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();
    expect(find.text('主题设置'), findsOneWidget);
    expect(find.text('主题模式'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.textContaining('功能开发中'), findsNothing);
  });

  testWidgets('主题设置：切换主题模式即时生效并持久化', (tester) async {
    await tester.pumpWidget(const MyApp());

    // 进入主题设置页
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();

    // 默认选中「跟随系统」：其单选标记为实心勾选
    final systemCheck = find.descendant(
      of: find.ancestor(of: find.text('跟随系统'), matching: find.byType(GestureDetector)),
      matching: find.byIcon(Icons.check_circle_rounded),
    );
    expect(systemCheck, findsOneWidget);

    // 切换到浅色：themeMode 即时变化，选择已持久化
    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    expect(await ThemeStorage.load(), ThemeMode.light);

    // 切换到深色：themeMode 即时变化，选择已持久化
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(await ThemeStorage.load(), ThemeMode.dark);

    // 深色下返回（此前停留在「更多」标签），切回首页后：
    // 卡片标题应使用深色调色板主文字色
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('单词PK').first).style?.color,
      AppPalette.dark.textPrimary,
    );

    // 切回跟随系统：恢复自动模式
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
  });

  testWidgets('主题设置：跟随系统时随系统深浅色自动切换', (tester) async {
    // 系统处于深色模式（通过平台分发器模拟系统深浅色设置）
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    await tester.pumpWidget(const MyApp());

    // 自动模式 + 系统深色：主页卡片标题使用深色调色板
    expect(
      tester.widget<Text>(find.text('单词PK').first).style?.color,
      AppPalette.dark.textPrimary,
    );

    // 系统切换到浅色：自动跟随为浅色调色板
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('单词PK').first).style?.color,
      AppPalette.light.textPrimary,
    );
  });

  testWidgets('主题色彩：预设色切换即时生效并持久化', (tester) async {
    await tester.pumpWidget(const MyApp());

    // 进入主题设置页
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();

    // 主题色彩卡片展示：默认品牌紫选中（对勾）、自定义入口存在
    expect(find.text('主题色彩'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('自定义颜色'), findsOneWidget);

    // 点击绿色预设：顶栏标题（强调色）立即变化并持久化
    const green = Color(0xFF2FBF71);
    await tester.tap(find.byKey(const ValueKey('preset_swatch_#2FBF71')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('主题设置')).style?.color,
      green,
    );
    expect(await ThemeStorage.loadSeedColor(), green);

    // 切回品牌紫：可再次切换
    await tester.tap(find.byKey(const ValueKey('preset_swatch_#7C5CFF')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('主题设置')).style?.color,
      AppPalette.brandPrimary,
    );
    expect(await ThemeStorage.loadSeedColor(), AppPalette.brandPrimary);
  });

  testWidgets('主题色彩：自定义颜色选择器调节并生效', (tester) async {
    await tester.pumpWidget(const MyApp());

    // 进入主题设置页并打开自定义颜色弹窗
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义颜色'));
    await tester.pumpAndSettle();

    // 弹窗展示：三通道滑块与操作按钮
    expect(find.text('自定义颜色'), findsWidgets);
    expect(find.text('色相'), findsOneWidget);
    expect(find.text('饱和度'), findsOneWidget);
    expect(find.text('亮度'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(3));
    expect(find.text('确定'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    // 拖动色相滑块改变颜色，点确定后生效并持久化
    await tester.drag(find.byType(Slider).first, const Offset(120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    final effective = tester.widget<Text>(find.text('主题设置')).style?.color;
    expect(effective, isNot(AppPalette.brandPrimary));
    expect(await ThemeStorage.loadSeedColor(), effective);

    // 重启（模拟 main 的恢复逻辑注入持久化颜色）后仍保持所选色彩：
    // UniqueKey 强制整树重建，避免 pumpWidget 复用旧 Element/路由栈
    await tester.pumpWidget(
      MyApp(
        key: UniqueKey(),
        themeController: ThemeController(
          ThemeMode.system,
          await ThemeStorage.loadSeedColor(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 回到主题设置页确认强调色未回退
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('主题设置')).style?.color,
      effective,
    );
  });

  testWidgets('设置页：其他模块关于入口', (tester) async {
    await tester.pumpWidget(const MyApp());

    // 切换到「更多」页，「其他」模块包含关于入口
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    expect(find.text('其他'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);

    // 点击进入关于页（当前为占位）
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    expect(find.textContaining('功能开发中'), findsOneWidget);
  });
}
