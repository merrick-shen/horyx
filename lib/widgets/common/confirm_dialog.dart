import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'dialog_action_button.dart';

/// 确认弹窗的操作结果
enum ConfirmResult {
  /// 点击确认按钮（主操作）
  confirm,

  /// 点击第三按钮（可选，如「不保存并退出」）
  neutral,

  /// 取消或关闭弹窗
  cancel,
}

/// 「保存并退出」三选项公共流程（各游戏对局页共用）
/// 弹出确认弹窗并分发动作：
/// - 保存并退出：先 [onSave] 持久化，完成后 [onExit]
/// - 不保存并退出：先 [onDiscard] 清档（放弃当前进度，避免下次误提示可继续），完成后 [onExit]
/// - 取消：留在当前页面
///
/// [state] 传调用方页面 State：弹窗与存档操作均为异步，
/// 期间页面可能已卸载，需以 State.mounted 守护后续 context 使用
Future<void> confirmExitWithArchive(
  State state, {
  required String title,
  required String message,
  required Future<void> Function() onSave,
  required Future<void> Function() onDiscard,
  required VoidCallback onExit,
}) async {
  final result = await showConfirmDialog(
    state.context,
    title: title,
    message: message,
    confirmLabel: '保存并退出',
    neutralLabel: '不保存并退出',
  );
  if (!state.mounted) return;

  switch (result) {
    case ConfirmResult.confirm:
      await onSave();
      if (state.mounted) onExit();
    case ConfirmResult.neutral:
      await onDiscard();
      if (state.mounted) onExit();
    case ConfirmResult.cancel:
      // 留在当前页面
      break;
  }
}

/// 通用确认弹窗
/// 自定义风格，与整体 UI 统一（配色随当前主题）
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
    final palette = context.palette;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: palette.surfaceBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            if (neutralLabel == null)
              // 两按钮：取消（描边）+ 确认（品牌色实底）横排
              Row(
                children: [
                  Expanded(
                    child: DialogActionButton(
                      label: cancelLabel,
                      onPressed: () =>
                          Navigator.of(context).pop(ConfirmResult.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DialogActionButton(
                      label: confirmLabel,
                      filled: true,
                      onPressed: () =>
                          Navigator.of(context).pop(ConfirmResult.confirm),
                    ),
                  ),
                ],
              )
            else ...[
              // 三按钮垂直布局：主操作最突出，取消弱化为文字按钮
              DialogActionButton(
                label: confirmLabel,
                filled: true,
                onPressed: () =>
                    Navigator.of(context).pop(ConfirmResult.confirm),
              ),
              const SizedBox(height: 10),
              DialogActionButton(
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
                  style: TextStyle(
                    color: palette.textSecondary,
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
