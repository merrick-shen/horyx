import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/setting_tile.dart';
import 'placeholder_page.dart';
import 'theme_settings_page.dart';

/// 设置页
/// 按模块分组展示设置项，新增模块在 [SettingsPage.build] 中扩展
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AppTopBar(title: '更多'),
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  // 平板/桌面端限制内容宽度，居中展示
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 「设置」模块：应用个性化配置
                          _SectionCard(
                            header: '设置',
                            children: [
                              SettingTile(
                                icon: Icons.palette_rounded,
                                title: '主题',
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const ThemeSettingsPage(),
                                    ),
                                  );
                                },
                              ),
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
                                onTap: () {
                                  // 关于页内容待开发，先复用通用占位页
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const PlaceholderPage(
                                        title: '关于',
                                        icon: Icons.info_outline_rounded,
                                      ),
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 设置分组卡片：小节标题 + 设置项列表
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.header, required this.children});

  /// 分组标题（如「设置」「其他」）
  final String header;

  /// 分组内的设置项
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              header,
              style: const TextStyle(
                color: AppColors.textSecondary,
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
