import 'package:flutter/material.dart';

import 'package:horyx/shared/storage/archive_storage.dart';
import 'package:horyx/shared/storage/game_archive_state.dart';
import 'package:horyx/shared/widgets/confirm_dialog.dart';

/// 对局页带存档的退出流程模板（各游戏对局页共用）：
/// 确认弹窗交互、存档保存与退出分发单点收敛于此

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
