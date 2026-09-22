import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/update/changelog_parser.dart';
import 'package:horyx/shared/widgets/app_page_scaffold.dart';
import 'package:horyx/shared/widgets/changelog_content_view.dart';
import 'package:horyx/shared/widgets/info_list_view.dart';

/// 更新日志页（版本列表）
/// 列表仅展示「版本号 + 发布日期 + 分类摘要」，点击进入详情页查看完整内容；
/// 内容直接读取打包进应用的 CHANGELOG.md 资源，与仓库文件保持一致：
/// 后续更新 CHANGELOG.md 后重新构建即可同步，无需在代码中维护第二份数据
class ChangelogPage extends StatefulWidget {
  const ChangelogPage({super.key});

  @override
  State<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<ChangelogPage> {
  /// 解析后的版本列表；null 表示加载中，空列表表示无内容
  List<ChangelogVersion>? _versions;

  @override
  void initState() {
    super.initState();
    _loadChangelog();
  }

  /// 读取并解析 CHANGELOG.md
  /// 资源随应用打包，正常不会失败；异常时置空列表展示占位文案，避免崩溃
  Future<void> _loadChangelog() async {
    try {
      final text = await rootBundle.loadString('CHANGELOG.md');
      if (mounted) setState(() => _versions = parseChangelogDocument(text));
    } catch (_) {
      if (mounted) setState(() => _versions = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: '更新日志',
      showBack: true,
      // 列表样式、加载/空态与点击交互统一由通用组件 InfoListView 承载
      child: InfoListView(
        items: _versions?.map(_toListItem).toList(),
        emptyText: '暂无更新内容',
      ),
    );
  }

  /// 将版本数据映射为通用列表条目；版本号 + 发布日期 + 分类摘要，点击进入详情页
  InfoListItem _toListItem(ChangelogVersion version) {
    return InfoListItem(
      // 已发布版本统一 v 前缀；「未发布」为特殊标识，不加前缀
      title:
          version.version == '未发布' ? version.version : 'v${version.version}',
      trailing: version.date,
      subtitle: _summary(version),
      // 与详情页大标题建立 Hero 共享元素过渡
      heroTag: 'changelog-version-${version.version}',
      onTap: () => Navigator.of(context).push(_VersionDetailRoute(version)),
    );
  }

  /// 分类条数摘要，如「变更 6 · 修复 7」
  String _summary(ChangelogVersion version) {
    return version.sections
        .map((s) => '${s.typeName} ${s.items.length}')
        .join(' · ');
  }
}

/// 版本详情页路由：淡入 + 轻微上滑的平滑过渡
/// 时长与曲线与底部导航切换一致（300ms easeOutCubic），保持全局动效统一
class _VersionDetailRoute extends PageRouteBuilder<void> {
  _VersionDetailRoute(ChangelogVersion version)
      : super(
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          pageBuilder: (context, animation, secondaryAnimation) =>
              _ChangelogDetailPage(version: version),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}

/// 版本详情页：完整展示该版本所有分类与变更条目
class _ChangelogDetailPage extends StatelessWidget {
  const _ChangelogDetailPage({required this.version});

  final ChangelogVersion version;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AppPageScaffold(
      title: '更新日志',
      showBack: true,
      child: Scrollbar(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            // 大号版本标题，承接列表卡片飞入的 Hero 过渡
            Hero(
              tag: 'changelog-version-${version.version}',
              child: Material(
                type: MaterialType.transparency,
                child: Text(
                  version.version == '未发布'
                      ? version.version
                      : 'v${version.version}',
                  style: TextStyle(
                    color: palette.primary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (version.date != null) ...[
              const SizedBox(height: 4),
              Text(
                // 发布日期，统一 YYYY-MM-DD（与 CHANGELOG.md 源格式一致）
                '发布于 ${version.date}',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
            // 分类与条目渲染统一由共享视图承载（与更新弹窗同一套样式）
            const SizedBox(height: 20),
            ChangelogContentView(sections: version.sections),
          ],
        ),
      ),
    );
  }
}
