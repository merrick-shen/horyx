import 'package:flutter/material.dart';

import '../services/theme_storage.dart';
import 'app_theme.dart';

/// 主题控制器
/// 持有当前主题状态（模式 + 强调色），变更时：
/// 1. 立即通知 UI 重建（MaterialApp 响应 themeMode / 调色板变化）
/// 2. 异步持久化到本地，保证应用重启后仍保持用户选择
/// 注意：先更新状态后写盘，界面切换不被存储耗时阻塞
class ThemeController extends ChangeNotifier {
  ThemeController([
    ThemeMode mode = ThemeMode.system,
    Color? seedColor,
  ])  : _mode = mode,
        _seedColor = seedColor ?? AppPalette.brandPrimary;

  ThemeMode _mode;

  /// 当前强调色（主题色彩）
  Color _seedColor;

  /// 当前主题模式
  ThemeMode get mode => _mode;

  /// 当前强调色
  Color get seedColor => _seedColor;

  /// 切换主题模式；重复设置同一模式时跳过，避免无谓刷新与写盘
  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    await ThemeStorage.save(mode);
  }

  /// 切换主题色彩；重复设置同一颜色时跳过，避免无谓刷新与写盘
  Future<void> setSeedColor(Color color) async {
    if (_seedColor == color) return;
    _seedColor = color;
    notifyListeners();
    await ThemeStorage.saveSeedColor(color);
  }
}

/// 主题控制器共享作用域
/// 挂在 MaterialApp 外层，任意页面（含 push 进入的设置页）经
/// ThemeScope.of(context) 获取控制器；controller 变化时依赖处自动重建
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  /// 获取最近祖先作用域中的主题控制器
  static ThemeController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()!.notifier!;
}
