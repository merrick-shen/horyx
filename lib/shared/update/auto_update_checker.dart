import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:horyx/shared/update/download_launcher.dart';
import 'package:horyx/shared/update/update_service.dart';
import 'package:horyx/shared/widgets/update_available_dialog.dart';

/// 自动检查更新：每次冷启动静默检查一次，仅「有新版本」时弹窗提示。
/// 无频控、无本地存储；检查失败与已是最新版完全无感（不打扰、不提示），
/// 下次启动自动重试。Debug 构建直接短路，开发期不被弹窗打扰。
class AutoUpdateChecker {
  AutoUpdateChecker({UpdateService? updateService})
    : _updateService = updateService ?? UpdateService();

  final UpdateService _updateService;

  /// Debug 短路开关：flutter test 环境恒为 Debug 构建，
  /// 默认取 kDebugMode；单测中覆写为 false 以验证三态分发
  @visibleForTesting
  static bool debugSkip = kDebugMode;

  /// 主流程：首帧后延迟 3 秒避开启动关键路径，再检查并按三态分发。
  /// 调用方在 initState 中 fire-and-forget 即可（post-frame 调度内置，
  /// 异常整体兜底，绝不影响正常使用）
  Future<void> checkIfNeeded(BuildContext context) async {
    if (debugSkip) return;
    try {
      // 请求与弹窗都需要完整的组件树：等首帧完成后再进入延迟等待
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(seconds: 3));

      final result = await _updateService.check();
      // 3 秒等待期间应用可能已退出：弹窗前确认上下文仍挂载
      if (!context.mounted) return;
      if (result case UpdateAvailable(:final release)) {
        final download = await showUpdateAvailableDialog(
          context,
          release: release,
        );
        // 用户选择「去下载」：与手动检查共用同一跳转与容错逻辑
        if (!context.mounted || !download) return;
        await launchDownload(context, release);
      }
      // UpdateUpToDate / UpdateCheckFailed：静默返回，无任何 UI
    } catch (e) {
      // 自动检查是附加能力，任何异常只记录线索、不干扰正常使用
      debugPrint('自动检查更新失败: $e');
    }
  }
}
