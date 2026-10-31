import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:horyx/shared/update/models/release_info.dart';
import 'package:horyx/shared/widgets/alert_dialog.dart';

/// 外部浏览器打开 [url]：无可处理该链接的应用等平台异常时以
/// [failMessage] 弹窗提示而非静默。跳转与容错逻辑只在此一处维护
/// （前往下载 / 打开项目仓库等外部跳转场景共用）
Future<void> launchExternal(
  BuildContext context,
  String url, {
  required String failMessage,
}) async {
  try {
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    // 异步间隙页面可能已关闭：不再弹提示
    if (!context.mounted) return;
    if (!launched) await showAlertDialog(context, message: failMessage);
  } catch (_) {
    if (context.mounted) await showAlertDialog(context, message: failMessage);
  }
}

/// 前往下载：外部浏览器接管（APK 直链或 Release 页面）
/// 关于页手动检查与启动自动检查共用
Future<void> launchDownload(BuildContext context, ReleaseInfo release) =>
    launchExternal(
      context,
      release.downloadUrl,
      failMessage: '无法打开下载页面',
    );
