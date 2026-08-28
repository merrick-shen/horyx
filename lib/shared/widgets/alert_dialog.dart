import 'package:flutter/material.dart';

import 'package:horyx/shared/theme/app_theme.dart';

/// 底部长条提示弹窗：校验错误等无需选择的告知场景
/// 从屏幕底部浮出，与居中卡片式确认弹窗（confirm_dialog.dart）区分场景：
/// 无遮罩（透明 barrier，点击条外区域也可关闭）、无标题，正文 + 「知道了」按钮
Future<void> showAlertDialog(
  BuildContext context, {
  required String message,
  String buttonLabel = '知道了',
}) {
  return showDialog<void>(
    context: context,
    // 提示类信息无需阻断式遮罩，保持页面可见，点击条外即可关闭
    barrierColor: Colors.transparent,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      // Dialog 自带对齐参数：底部居中呈现长条形态
      alignment: Alignment.bottomCenter,
      // 底部避让系统手势区，左右与页面内容边距一致
      insetPadding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.paddingOf(dialogContext).bottom + 20,
      ),
      child: _AlertDialogBar(message: message, buttonLabel: buttonLabel),
    ),
  );
}

/// 长条提示条：警示图标 + 完整正文 + 确认按钮
class _AlertDialogBar extends StatelessWidget {
  const _AlertDialogBar({required this.message, required this.buttonLabel});

  /// 提示正文（通知类 UI，完整展示不截断）
  final String message;

  /// 确认按钮文案
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: palette.surfaceBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.stroke),
        boxShadow: [
          // 底部浮层需要投影与页面内容区分层（中性黑投影，避免主题色光晕喧宾夺主）
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: palette.primary,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 小号实底按钮：与 DialogActionButton 实底态同一视觉语言（主题色 + 白字）
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: palette.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                buttonLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
