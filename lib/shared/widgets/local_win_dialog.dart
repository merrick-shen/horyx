import 'package:flutter/material.dart';

import 'package:horyx/shared/widgets/confirm_dialog.dart';

/// 本地对局终局胜负弹窗（chess / gomoku / aeroplane 本地页共用）：
/// 确认「再来一局」重开，中键「返回设置」回设置视图，取消留在终局棋盘查看。
/// 三页此前为逐行同构的 showConfirmDialog + switch 骨架，收敛于此唯一定义
Future<void> showLocalWinDialog(
  BuildContext context, {
  required String winner,
  required String message,
  required VoidCallback onRestart,
  required VoidCallback onBackToSetup,
}) async {
  final result = await showConfirmDialog(
    context,
    title: '$winner胜利！',
    message: message,
    confirmLabel: '再来一局',
    neutralLabel: '返回设置',
  );
  if (!context.mounted) return;
  if (result == ConfirmResult.confirm) {
    onRestart();
  } else if (result == ConfirmResult.neutral) {
    onBackToSetup();
  }
}
