import 'package:flutter/material.dart';

import 'package:horyx/shared/storage/archive_storage.dart';

/// 游戏页存档状态管理基类（配合 [ArchiveStorage] 使用）
/// 统一各游戏页「进入时检测未完成对局 → 设置视图展示恢复入口」的
/// 同构部分：存档字段持有 + 异步加载（含 mounted 检查与 setState）。
/// 恢复时的字段还原（各游戏模型不同）保留在页面 _resumeSaved 中，
/// 页面在 setState 内直接置 savedState = null 关闭恢复入口。
/// 用基类而非 mixin：Dart 的 mixin on `State<T>` 约束会与具体页面的
/// `State<页面类型>` 产生泛型接口冲突，基类双泛型则无此问题
abstract class GameArchiveStateBase<W extends StatefulWidget,
    T extends GameArchiveSummary> extends State<W> {
  /// 各游戏的存档服务（如 WordPkStorage.instance）
  ArchiveStorage<T> get archiveStorage;

  /// 进入时检测到的未完成存档；恢复或开始新对局后置 null 关闭入口
  T? savedState;

  /// 当前是否仍处于设置阶段（恢复入口只在设置视图展示）
  /// 用于丢弃迟到的加载结果：加载是毫秒级异步，若用户恰好在其间
  /// 点了"开始对局"（savedState 已置 null），旧恢复入口不应复活
  bool get isInSetupPhase;

  /// 检测未完成对局，存在则刷新恢复入口（initState 调用；
  /// 计分器退出计分回到设置视图后也会重新调用刷新）
  Future<void> loadSavedState() async {
    final state = await archiveStorage.load();
    if (state != null && mounted && isInSetupPhase) {
      setState(() => savedState = state);
    }
  }
}
