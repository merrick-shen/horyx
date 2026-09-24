import 'package:flutter/material.dart';

import 'package:horyx/app/pages/settings/profile_settings_page.dart';
import 'package:horyx/shared/storage/profile_storage.dart';
import 'package:horyx/shared/widgets/confirm_dialog.dart';

/// 用户资料控制器
/// 持有当前用户名（null = 未设置），setName 时：
/// 1. 立即通知 UI 重建（更多页副标题等依赖处实时刷新）
/// 2. 异步持久化到本地，保证应用重启后仍保持
/// 注意：先更新状态后写盘，界面刷新不被存储耗时阻塞
class ProfileController extends ChangeNotifier {
  ProfileController([this._name]);

  String? _name;

  /// 当前用户名；null = 未设置
  String? get name => _name;

  /// 设置名字；重复设置同一名字时跳过，避免无谓刷新与写盘
  Future<void> setName(String name) async {
    if (_name == name) return;
    _name = name;
    notifyListeners();
    try {
      await ProfileStorage.save(name);
    } catch (e) {
      // 写盘失败仅影响重启后的名字恢复，UI 已即时生效不阻断交互，
      // 与 ThemeController 写盘侧的容错风格对齐
      debugPrint('ProfileStorage.save 失败（名字仅本次会话生效）: $e');
    }
  }
}

/// 用户资料控制器共享作用域
/// 挂在 MaterialApp 外层，任意页面（含 push 进入的设置页）经
/// ProfileScope.of(context) 获取控制器；controller 变化时依赖处自动重建
class ProfileScope extends InheritedNotifier<ProfileController> {
  const ProfileScope({
    super.key,
    required ProfileController controller,
    required super.child,
  }) : super(notifier: controller);

  /// 获取最近祖先作用域中的用户资料控制器
  static ProfileController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProfileScope>()!.notifier!;
}

/// 联机前名字引导
/// 名字已设置直接返回 true；未设置时先弹确认弹窗，确认后跳转个人资料
/// 设置页，保存成功（pop(true)）返回 true；取消弹窗或在设置页未保存
/// 返回均返回 false，调用方据此中断本次联机操作（可随时重新发起）
Future<bool> ensureProfileForOnline(BuildContext context) async {
  if (ProfileScope.of(context).name != null) return true;
  final result = await showConfirmDialog(
    context,
    title: '设置你的名字',
    message: '联机时好友将看到这个名字',
    confirmLabel: '去设置',
  );
  if (result != ConfirmResult.confirm || !context.mounted) return false;
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const ProfileSettingsPage()),
  );
  return saved == true;
}
