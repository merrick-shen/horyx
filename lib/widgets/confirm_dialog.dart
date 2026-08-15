import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 确认弹窗的操作结果
enum ConfirmResult {
  /// 点击确认按钮（主操作）
  confirm,

  /// 点击第三按钮（可选，如「不保存并退出」）
  neutral,

  /// 取消或关闭弹窗
  cancel,
}

/// 通用确认弹窗
/// 自定义深色风格，与整体 UI 统一
/// 默认两按钮（取消/确认）横排；传入 [neutralLabel] 时为垂直三按钮布局
Future<ConfirmResult> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = '取消',
  String? neutralLabel,
}) async {
  final result = await showDialog<ConfirmResult>(
    context: context,
    builder: (_) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      neutralLabel: neutralLabel,
    ),
  );
  return result ?? ConfirmResult.cancel;
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    this.neutralLabel,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;

  /// 可选第三按钮文案；非空时采用垂直三按钮布局
  final String? neutralLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppColors.surfaceBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            if (neutralLabel == null)
              // 两按钮：取消（描边）+ 确认（渐变）横排
              Row(
                children: [
                  Expanded(
                    child: _DialogButton(
                      label: cancelLabel,
                      onPressed: () =>
                          Navigator.of(context).pop(ConfirmResult.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DialogButton(
                      label: confirmLabel,
                      gradient: true,
                      onPressed: () =>
                          Navigator.of(context).pop(ConfirmResult.confirm),
                    ),
                  ),
                ],
              )
            else ...[
              // 三按钮垂直布局：主操作最突出，取消弱化为文字按钮
              _DialogButton(
                label: confirmLabel,
                gradient: true,
                onPressed: () =>
                    Navigator.of(context).pop(ConfirmResult.confirm),
              ),
              const SizedBox(height: 10),
              _DialogButton(
                label: neutralLabel!,
                onPressed: () =>
                    Navigator.of(context).pop(ConfirmResult.neutral),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(ConfirmResult.cancel),
                child: Text(
                  cancelLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 弹窗按钮：默认描边样式，[gradient] 为 true 时使用品牌渐变主按钮样式
class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.onPressed,
    this.gradient = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: gradient
              ? const LinearGradient(colors: AppColors.brandGradient)
              : null,
          color: gradient ? null : AppColors.scaffoldBg,
          borderRadius: BorderRadius.circular(13),
          border: gradient
              ? null
              : Border.all(color: AppColors.stroke),
          boxShadow: gradient
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: gradient ? Colors.white : AppColors.textPrimary,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
