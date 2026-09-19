import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:horyx/shared/update/models/release_info.dart';
import 'package:horyx/shared/widgets/alert_dialog.dart';

/// 前往下载：外部浏览器接管（APK 直链或 Release 页面）
/// 关于页手动检查与启动自动检查共用，跳转与容错逻辑只在此一处维护；
/// 调用方需在发起前自行确认页面仍处于挂载状态（如检查 State.mounted）
Future<void> launchDownload(BuildContext context, ReleaseInfo release) async {
  try {
    final launched = await launchUrl(
      Uri.parse(release.downloadUrl),
      mode: LaunchMode.externalApplication,
    );
    // 异步间隙页面可能已关闭：不再弹提示
    if (!context.mounted) return;
    // 无可处理该链接的应用等平台异常：提示用户而非静默
    if (!launched) await showAlertDialog(context, message: '无法打开下载页面');
  } catch (_) {
    if (context.mounted) {
      await showAlertDialog(context, message: '无法打开下载页面');
    }
  }
}
