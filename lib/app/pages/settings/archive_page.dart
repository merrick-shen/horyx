import 'package:flutter/material.dart';

import 'package:horyx/app/game_registry.dart';
import 'package:horyx/shared/game/game_info.dart';
import 'package:horyx/shared/storage/archive_storage.dart';
import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/widgets/app_page_scaffold.dart';
import 'package:horyx/shared/widgets/confirm_dialog.dart';
import 'package:horyx/shared/widgets/page_content.dart';
import 'package:horyx/shared/widgets/panel_card.dart';

/// 存档管理页
/// 平铺混排展示所有游戏的全部未完成对局存档（不按游戏分类），
/// 按保存时间倒序排列，支持逐条开始（定点恢复该档进入对局）与删除
/// 删除前弹确认弹窗，确认后清除对应存档并刷新列表。
/// 条目数据由 ArchiveStorage.loadAllSummaries 统一读出（一次读索引即可，
/// 摘要/时间为冗余副本无需解析数据键），游戏名称/图标经 gameId 关联
/// GameRegistry 取得，删除经各游戏登记的 GameArchiveInfo.remove 执行
class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key});

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  /// 存档条目列表（按 GameRegistry 登记顺序展示，与首页卡片一致）
  List<_ArchiveEntry> _entries = [];

  /// 数据加载完成标记：区分「加载中」与「无存档」两种空列表状态
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadArchives();
  }

  /// 读取全部游戏的存档索引并组装展示条目（按保存时间倒序，
  /// 不同游戏混排平铺，不按游戏分类）；未登记游戏的孤立条目跳过
  /// （正常不会出现，防御索引残留）；
  /// 单条索引损坏不影响其余展示（索引读取内部已按条跳过）
  Future<void> _loadArchives() async {
    final entries = <_ArchiveEntry>[];
    for (final item in await ArchiveStorage.loadAllSummaries()) {
      final game = GameRegistry.byName(item.gameId);
      final archive = game?.archive;
      if (game == null || archive == null) continue;
      entries.add(_ArchiveEntry(
        name: game.name,
        icon: game.icon,
        summary: item.summary,
        savedAt: item.savedAt,
        start: () => _openGame(game, item.id),
        remove: () => archive.remove(item.id),
      ));
    }

    if (mounted) {
      setState(() {
        _entries = entries;
        _loaded = true;
      });
    }
  }

  /// 时间格式化为「MM-dd HH:mm」，避免引入 intl 依赖
  String _formatTime(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  /// 定点开始：跳入对应游戏并直接恢复该条存档（页面经 resumeArchiveId
  /// 加载该档进入对局，此后保存覆盖该档）；返回后刷新列表
  /// （游玩期间可能保存新档或删除存档，展示集合已变化）
  Future<void> _openGame(GameInfo game, String archiveId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            game.pageBuilder(context, resumeArchiveId: archiveId),
      ),
    );
    if (mounted) await _loadArchives();
  }

  /// 删除确认：弹窗确认后删除对应存档条目并刷新列表
  Future<void> _confirmRemove(_ArchiveEntry entry) async {
    final result = await showConfirmDialog(
      context,
      title: '删除存档？',
      message:
          '将删除「${entry.name}」保存于 ${_formatTime(entry.savedAt)} 的未完成对局存档，删除后无法恢复',
      confirmLabel: '删除',
      cancelLabel: '取消',
    );
    if (!mounted || result != ConfirmResult.confirm) return;

    try {
      await entry.remove();
    } catch (e) {
      // 删除失败（存储异常）不阻断流程：刷新后条目仍在列表中可重试，
      // 与 main 启动时读取侧的容错风格对齐
      debugPrint('存档删除失败: $e');
    }
    if (!mounted) return;
    // 重新读取存档刷新列表（删除后可能无存档，自动切换空状态）
    await _loadArchives();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AppPageScaffold(
      title: '存档管理',
      showBack: true,
      child: SingleChildScrollView(
        child: PageContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_entries.isNotEmpty) ...[
                // 说明文案：存档来源
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 12),
                  child: Text(
                    '所有游戏的未完成对局存档，按保存时间倒序，删除后无法恢复',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                // 存档条目列表
                for (final entry in _entries) ...[
                  _ArchiveTile(
                    entry: entry,
                    timeText: _formatTime(entry.savedAt),
                    onStart: entry.start,
                    onDelete: () => _confirmRemove(entry),
                  ),
                  const SizedBox(height: 12),
                ],
              ] else if (_loaded) ...[
                // 无存档空状态
                _EmptyView(),
              ],
              // 加载中阶段（_loaded 为 false）不渲染内容，
              // 本地存储读取很快，无需专门 loading 指示
            ],
          ),
        ),
      ),
    );
  }
}

/// 单个存档条目：游戏图标 + 名称/摘要 + 保存时间 + 开始/删除按钮
class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile({
    required this.entry,
    required this.timeText,
    required this.onStart,
    required this.onDelete,
  });

  final _ArchiveEntry entry;

  /// 已格式化的保存时间文本
  final String timeText;

  /// 点击开始按钮回调（由页面跳入对应游戏定点恢复该条存档）
  final VoidCallback onStart;

  /// 点击删除按钮回调（由页面弹确认弹窗后执行删除）
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return PanelCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // 主题色淡底图标容器（与设置行图标风格一致）
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            child: Icon(entry.icon, color: palette.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  entry.summary,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '保存于 $timeText',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 开始按钮：点击后跳入对应游戏恢复该条存档
          IconButton(
            icon: Icon(
              Icons.play_arrow_rounded,
              color: palette.primary,
              size: 26,
            ),
            onPressed: onStart,
          ),
          // 删除按钮：点击后由页面弹确认弹窗
          IconButton(
            icon: Icon(
              Icons.delete_outline_rounded,
              color: palette.textSecondary,
              size: 22,
            ),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// 无存档空状态
class _EmptyView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 56,
            color: palette.textSecondary,
          ),
          const SizedBox(height: 14),
          Text(
            '暂无存档',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '游戏中保存并退出后，未完成的对局会出现在这里',
            style: TextStyle(color: palette.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// 存档展示条目数据
class _ArchiveEntry {
  const _ArchiveEntry({
    required this.name,
    required this.icon,
    required this.summary,
    required this.savedAt,
    required this.start,
    required this.remove,
  });

  /// 游戏名（与主页卡片一致）
  final String name;

  /// 游戏图标（与 GameRegistry 一致）
  final IconData icon;

  /// 进度摘要（与各游戏恢复卡片文案一致）
  final String summary;

  /// 存档时间
  final DateTime savedAt;

  /// 定点开始该存档（跳入对应游戏并恢复该档）
  final VoidCallback start;

  /// 删除该存档条目（按 id 精确移除）
  final Future<void> Function() remove;
}
