import 'package:flutter/material.dart';

import 'package:horyx/shared/profile/profile_controller.dart';
import 'package:horyx/shared/storage/auto_update_storage.dart';
import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/widgets/app_page_scaffold.dart';
import 'package:horyx/shared/widgets/panel_card.dart';
import 'package:horyx/shared/widgets/page_content.dart';
import 'package:horyx/shared/widgets/setting_tile.dart';
import 'package:horyx/app/pages/settings/about_page.dart';
import 'package:horyx/app/pages/settings/archive_page.dart';
import 'package:horyx/app/pages/settings/profile_settings_page.dart';
import 'package:horyx/app/pages/settings/theme_settings_page.dart';

/// 更多页
/// 按模块分组展示设置项，新增模块在 [MorePage.build] 中扩展
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    // ProfileScope 依赖：名字变化时本页重建，副标题实时刷新
    final profileName = ProfileScope.of(context).name;

    return AppPageScaffold(
      title: '更多',
      child: SingleChildScrollView(
        child: PageContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 「设置」模块：应用个性化配置
              _SectionCard(
                header: '设置',
                children: [
                  SettingTile(
                    icon: Icons.person_rounded,
                    title: '个人资料',
                    subtitle: profileName ?? '未设置',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ProfileSettingsPage(),
                        ),
                      );
                    },
                  ),
                  SettingTile(
                    icon: Icons.palette_rounded,
                    title: '主题',
                    subtitle: '主题模式与色彩定制',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ThemeSettingsPage(),
                        ),
                      );
                    },
                  ),
                  // 存档管理：查看并清除各游戏未完成对局
                  SettingTile(
                    icon: Icons.inventory_2_rounded,
                    title: '存档管理',
                    subtitle: '查看并清除未完成对局',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ArchivePage(),
                        ),
                      );
                    },
                  ),
                  // 自动检查更新开关：控制启动时的静默检查（默认开启）
                  const _AutoUpdateToggleTile(),
                ],
              ),
              const SizedBox(height: 14),
              // 「其他」模块：辅助信息
              _SectionCard(
                header: '其他',
                children: [
                  SettingTile(
                    icon: Icons.info_outline_rounded,
                    title: '关于',
                    subtitle: '应用信息、更新与开源许可',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AboutPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分组卡片：小节标题 + 设置项列表
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.header, required this.children});

  /// 分组标题（如「设置」「其他」）
  final String header;

  /// 分组内的设置项
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // 卡片容器样式复用 PanelCard；设置行自带内边距，故面板整体 padding 归零
    return PanelCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              header,
              style: TextStyle(
                color: context.palette.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// 自动检查更新开关行：右侧 Switch，点击整行或开关均可切换；
/// 状态经 AutoUpdateStorage 持久化（未设置默认开启）
class _AutoUpdateToggleTile extends StatefulWidget {
  const _AutoUpdateToggleTile();

  @override
  State<_AutoUpdateToggleTile> createState() => _AutoUpdateToggleTileState();
}

class _AutoUpdateToggleTileState extends State<_AutoUpdateToggleTile> {
  /// 当前开关状态；null = 尚未从存储加载完成（UI 先按默认开启渲染）
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    AutoUpdateStorage.load().then((enabled) {
      if (mounted) setState(() => _enabled = enabled);
    });
  }

  Future<void> _toggle() async {
    final next = !(_enabled ?? true);
    setState(() => _enabled = next);
    await AutoUpdateStorage.save(next);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled ?? true;
    return SettingTile(
      icon: Icons.sync_rounded,
      title: '自动检查更新',
      subtitle: '应用启动时检测新版本',
      onTap: _toggle,
      trailing: Switch(
        value: enabled,
        onChanged: _enabled == null ? null : (_) => _toggle(),
      ),
    );
  }
}
