import 'package:flutter/material.dart';

import 'package:horyx/shared/storage/archive_storage.dart';
import 'package:horyx/shared/storage/game_archive_state.dart';
import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/widgets/dialog_action_button.dart';
import 'package:horyx/shared/widgets/dialog_shell.dart';

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
/// - 保存并退出：先 [onSave] 持久化，完成后 [onExit]；保存失败时弹窗告知，
///   由用户选择「仍要退出」或留在本页
/// - 直接退出：不写不清档（磁盘存档保持原样，下次仍可恢复），直接 [onExit]
/// - 取消：留在当前页面
///
/// [title]/[message] 有统一默认文案，各游戏无需再传；
/// 场景特殊时（如计分器）可覆盖
///
/// [state] 传调用方页面 State：弹窗与存档操作均为异步，
/// 期间页面可能已卸载，需以 State.mounted 守护后续 context 使用
Future<void> confirmExitWithArchive(
  State state, {
  String title = '退出对局？',
  String message = '保存并退出后，下次进入可从当前进度继续',
  required Future<void> Function() onSave,
  required VoidCallback onExit,
}) async {
  final result = await showConfirmDialog(
    state.context,
    title: title,
    message: message,
    confirmLabel: '保存并退出',
    neutralLabel: '直接退出',
  );
  if (!state.mounted) return;

  switch (result) {
    case ConfirmResult.confirm:
      // 写盘失败（磁盘满、插件异常等）不能沿 async 链上抛：否则异常无人捕获，
      // 且 onExit 不执行导致用户点「保存并退出」后页面毫无反馈也无法退出
      try {
        await onSave();
      } catch (_) {
        if (!state.mounted) return;
        // 保存失败必须告知（用户以为进度已存，实际下次进入会丢失），
        // 并由用户决定是否放弃保存直接退出
        final forceExit = await showConfirmDialog(
          state.context,
          title: '保存失败',
          message: '进度未能保存，退出后本次进度将丢失，是否仍要退出？',
          confirmLabel: '仍要退出',
        );
        if (!state.mounted || forceExit != ConfirmResult.confirm) return;
      }
      if (state.mounted) onExit();
    case ConfirmResult.neutral:
      // 不写不清档：磁盘存档保持原样，下次进入仍可恢复
      if (state.mounted) onExit();
    case ConfirmResult.cancel:
      // 留在当前页面
      break;
  }
}

/// 对局页退出请求模板方法（各游戏 `_requestExit` 的同构骨架，三段式）：
/// 1. [hasProgress] 为 false：无进行中对局（未进入对局/已终局/终局查看），
///    直接 [exitPage] 退出页面；
/// 2. [hasMoves] 为 false：开局后尚无落子/提交——不打扰，执行
///    [onBackToSetup] 清对局状态回设置视图，随后统一 [loadSavedState]
///    刷新恢复入口（开局时入口已被置空，未走子即退出时磁盘上的旧存档
///    仍在，回设置后应重新展示）；
/// 3. [unchangedSinceRestore] 为 true：恢复存档后未产生新进度（状态与
///    恢复基线一致），直接 [exitPage] 退出且不写不清档，存档保持原样；
/// 4. 其余：弹出三选项确认（见 [confirmExitWithArchive]）——保存并退出
///    执行 [onSave]（各游戏组装存档模型）；直接退出不写不清档
///    （存档保持原样，下次仍可恢复）；取消留在本页。
///
/// [title]/[message] 透传给确认弹窗：默认文案面向棋局对弈措辞，
/// 计分器等场景可覆盖（如「退出计分？」）
///
/// 坦克动荡不走本模板：其存档状态在父级页面（TankPage），对局页并非
/// [GameArchiveStateBase]，仍直接使用 [confirmExitWithArchive]
///
/// [state] 传调用方页面 State：弹窗与存档操作均为异步，
/// 期间页面可能已卸载，需以 State.mounted 守护后续 context 使用
Future<void> requestExitWithArchive<W extends StatefulWidget,
    T extends GameArchiveSummary>(
  GameArchiveStateBase<W, T> state, {
  required bool hasProgress,
  required bool hasMoves,
  required bool unchangedSinceRestore,
  String title = '退出对局？',
  String message = '保存并退出后，下次进入可从当前进度继续',
  required Future<void> Function() onSave,
  required VoidCallback onBackToSetup,
  required VoidCallback exitPage,
}) async {
  if (!hasProgress) {
    exitPage();
    return;
  }
  if (!hasMoves) {
    onBackToSetup();
    // 回设置后重新检测存档刷新恢复入口（见方法注释第 2 步）
    await state.loadSavedState();
    return;
  }
  // 恢复存档后未产生新进度（状态与恢复基线一致，含悔棋净零变化）：
  // 直接退出且不写不清档，磁盘存档保持原样，下次仍可恢复同一进度
  if (unchangedSinceRestore) {
    exitPage();
    return;
  }
  await confirmExitWithArchive(
    state,
    title: title,
    message: message,
    onSave: onSave,
    onExit: exitPage,
  );
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

    return DialogShell(
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
            // 两按钮：取消（描边）+ 确认（主题色实底）横排
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
    );
  }
}
