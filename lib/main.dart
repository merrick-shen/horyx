import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/app_shell.dart';
import 'services/theme_storage.dart';
import 'services/word_validator.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

/// 应用入口
Future<void> main() async {
  // 词表加载依赖 rootBundle，需先初始化绑定
  WidgetsFlutterBinding.ensureInitialized();
  await WordValidator.load();
  // 启动时恢复用户上次选择的主题模式，避免重启后闪回默认深色
  final themeMode = await ThemeStorage.load();
  runApp(MyApp(themeController: ThemeController(themeMode)));
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
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
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
