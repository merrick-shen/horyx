import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/app_top_bar.dart';

/// 主题模式选项定义：模式 + 图标 + 名称 + 描述
typedef _ModeOptionData = ({
  ThemeMode mode,
  IconData icon,
  String name,
  String description,
});

/// 主题设置页
/// 当前提供主题模式切换（跟随系统/深色/浅色），选择后全局即时生效并持久化保存
/// 主题色彩模块待开发，后续在同一页面扩展
class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  /// 主题模式选项列表
  static const List<_ModeOptionData> _options = [
    (
      mode: ThemeMode.system,
      icon: Icons.brightness_auto_rounded,
      name: '跟随系统',
      description: '随系统深浅色设置自动切换',
    ),
    (
      mode: ThemeMode.dark,
      icon: Icons.dark_mode_rounded,
      name: '深色',
      description: '始终使用深色配色',
    ),
    (
      mode: ThemeMode.light,
      icon: Icons.light_mode_rounded,
      name: '浅色',
      description: '始终使用浅色配色',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // InheritedNotifier 依赖：模式变化时本页自动重建，选中态即时刷新
    final controller = ThemeScope.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppTopBar(
              title: '主题设置',
              leading: IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: context.palette.textPrimary,
                  size: 20,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
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
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: context.palette.surfaceBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: context.palette.stroke),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(0, 0, 0, 10),
                                  child: Text(
                                    '主题模式',
                                    style: TextStyle(
                                      color: context.palette.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                for (final option in _options)
                                  _ModeOption(
                                    data: option,
                                    selected: controller.mode == option.mode,
                                    onTap: () =>
                                        controller.setMode(option.mode),
                                  ),
                              ],
                            ),
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

/// 主题模式选项行：图标 + 名称/描述 + 单选标记
/// 选中态以品牌色描边 + 淡底点亮，与人数选择块的选中风格一致
class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _ModeOptionData data;

  /// 是否为当前生效模式
  final bool selected;

  /// 点击回调
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          // 选中态：品牌淡底 + 品牌描边；未选中：透明底 + 常规描边
          color: selected
              ? palette.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? palette.primary.withValues(alpha: 0.5)
                : palette.stroke,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                // 选中态图标块用品牌实底反色，强化当前选择
                color: selected
                    ? palette.primary
                    : palette.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                data.icon,
                size: 20,
                color: selected ? Colors.white : palette.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.name,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    data.description,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              // 单选标记：选中实心品牌色，未选中空心描边
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              color: selected ? palette.primary : palette.stroke,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
