import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:horyx/app/app_shell.dart';
import 'package:horyx/shared/storage/theme_storage.dart';
import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/theme/theme_controller.dart';

/// 应用入口
Future<void> main() async {
  // 主题恢复依赖存储插件通道，需先初始化绑定
  WidgetsFlutterBinding.ensureInitialized();
  // 启动时恢复用户上次选择的主题模式与主题色彩，避免重启后回退默认值；
  // 极端平台异常（存储初始化失败等）时回退默认主题，保证应用可正常启动
  var themeMode = ThemeMode.system;
  var seedColor = AppPalette.brandPrimary;
  try {
    themeMode = await ThemeStorage.load();
    seedColor = await ThemeStorage.loadSeedColor();
  } catch (_) {
    // 初始化失败不阻断启动，使用与 ThemeController 默认值一致的主题
  }
  runApp(MyApp(themeController: ThemeController(themeMode, seedColor)));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.themeController});

  /// 主题控制器；main 中注入持久化恢复后的实例
  /// 省略时（如测试）内部创建默认控制器（跟随系统）
  final ThemeController? themeController;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ThemeController _controller;

  /// 是否由本组件创建控制器（创建方负责销毁，避免双重 dispose）
  late final bool _ownsController;

  /// 全局路由观察器（见 [_UnfocusOnRoutePushObserver]）；State 持有稳定实例，
  /// 主题切换重建 MaterialApp 时不会反复创建观察器
  final NavigatorObserver _unfocusOnPushObserver =
      _UnfocusOnRoutePushObserver();

  @override
  void initState() {
    super.initState();
    if (widget.themeController != null) {
      _controller = widget.themeController!;
      _ownsController = false;
    } else {
      _controller = ThemeController();
      _ownsController = true;
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // 监听控制器：主题模式变化时重建 MaterialApp，实现全局实时切换
      animation: _controller,
      builder: (context, _) => ThemeScope(
        controller: _controller,
        child: MaterialApp(
          title: 'Horyx',
          debugShowCheckedModeBanner: false,
          // 全局导航失焦：任意页面推入时收起键盘（见观察器注释）
          navigatorObservers: [_unfocusOnPushObserver],
          // 强调色由用户选择的主题色彩决定，随控制器实时重建
          theme: AppTheme.lightOf(_controller.seedColor),
          darkTheme: AppTheme.darkOf(_controller.seedColor),
          // 自动模式由系统深浅色决定实际生效主题
          themeMode: _controller.mode,
          // 所有路由（含 push 页面）统一在此处理状态栏样式：
          // 图标颜色需与实际生效主题的背景亮度匹配，否则时间/电量不可读
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: Theme.of(context).brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            child: child!,
          ),
          home: const AppShell(),
        ),
      ),
    );
  }
}

/// 全局路由推入失焦观察器：任意路由（页面/弹窗）推入时收起键盘并释放焦点。
/// 修复：联机页输入框聚焦后焦点永久保留——推入新路由使其失去主焦点
/// 但仍被记录为可恢复焦点，退出该路由时框架恢复焦点导致键盘自动弹出
/// （如聚焦后进游戏/更新日志再退出）；推入时统一失焦，返回即无可恢复焦点
class _UnfocusOnRoutePushObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    FocusManager.instance.primaryFocus?.unfocus();
  }
}
