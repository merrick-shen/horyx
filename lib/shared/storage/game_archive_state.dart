import 'package:flutter/material.dart';

import 'package:horyx/shared/storage/archive_storage.dart';

/// 游戏页存档状态管理基类（配合 [ArchiveStorage] 使用）
/// 统一各游戏页「进入时检测未完成对局 → 设置视图展示恢复入口」的
/// 同构部分：存档字段持有 + 异步加载（含 mounted 检查与 setState）。
/// 多存档下恢复入口仅展示该游戏最新一条存档；恢复后保存走覆盖更新，
/// 开新对局保存新建存档。恢复时的字段还原（各游戏模型不同）保留在
/// 页面 _resumeSaved 中，页面经 [takeResumeEntry] 消费恢复入口。
/// 用基类而非 mixin：Dart 的 mixin on `State<T>` 约束会与具体页面的
/// `State<页面类型>` 产生泛型接口冲突，基类双泛型则无此问题
abstract class GameArchiveStateBase<W extends StatefulWidget,
    T extends GameArchiveSummary> extends State<W> {
  /// 各游戏的存档服务（如 WordPkStorage.instance）
  ArchiveStorage<T> get archiveStorage;

  /// 进入时检测到的未完成存档；恢复或开始新对局后置 null 关闭入口
  T? savedState;

  /// 当前对局绑定的存档 id：进入页面时绑定为最新一条（恢复后保存覆盖
  /// 该档）；开始新对局（[discardResumeEntry]）后解绑，保存新建存档；
  /// 首次保存后重新绑定（此后保存与终局清档定位同一档）
  String? resumedArchiveId;

  /// 当前是否仍处于设置阶段（恢复入口只在设置视图展示）
  /// 用于丢弃迟到的加载结果：加载是毫秒级异步，若用户恰好在其间
  /// 点了"开始对局"（savedState 已置 null），旧恢复入口不应复活
  bool get isInSetupPhase;

  /// 检测该游戏最新一条存档，存在则刷新恢复入口并绑定覆盖目标
  /// （initState 调用；计分器退出计分回到设置视图后也会重新调用刷新）
  Future<void> loadSavedState() async {
    final record = await archiveStorage.loadLatest();
    if (record != null && mounted && isInSetupPhase) {
      setState(() {
        savedState = record.state;
        resumedArchiveId = record.id;
      });
    }
  }

  /// 保存当前对局进度：已绑定存档则覆盖更新，否则新建存档。
  /// 保存后绑定到该存档，保证后续保存与终局清档定位同一档
  Future<String> saveCurrent(T state) async {
    final id = await archiveStorage.saveArchive(state, id: resumedArchiveId);
    resumedArchiveId = id;
    return id;
  }

  /// 开始新对局：关闭恢复入口并解绑覆盖目标，此后保存新建存档
  void discardResumeEntry() {
    savedState = null;
    resumedArchiveId = null;
  }

  /// 消费恢复入口：返回待恢复存档并关闭入口（此后保存覆盖该档）；
  /// 无可恢复内容时返回 null
  T? takeResumeEntry() {
    final saved = savedState;
    if (saved == null) return null;
    savedState = null;
    return saved;
  }

  /// 终局清档：删除当前对局绑定的存档并解绑；
  /// 未绑定（新对局且未保存过）时无档可删，无操作
  Future<void> clearCurrentArchive() async {
    final id = resumedArchiveId;
    if (id == null) return;
    resumedArchiveId = null;
    await archiveStorage.remove(id);
  }
}
