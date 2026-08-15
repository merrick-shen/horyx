import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/services/theme_storage.dart';
import 'package:horyx/theme/app_theme.dart';
import 'package:horyx/theme/theme_controller.dart';
import 'package:horyx/main.dart';

import 'helpers/test_app.dart';

/// 设置页与主题功能测试
void main() {
  setUpTestEnv();

  testWidgets('设置页：主题入口跳转主题设置页', (tester) async {
    await pumpApp(tester);

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
    await pumpApp(tester);

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
    await pumpApp(tester);

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
    await pumpApp(tester);

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
    await pumpApp(tester);

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
    await pumpApp(tester);

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
