import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/color_picker_dialog.dart';

/// 主题模式选项定义：模式 + 图标 + 名称 + 描述
typedef _ModeOptionData = ({
  ThemeMode mode,
  IconData icon,
  String name,
  String description,
});

/// 主题设置页
/// 主题模式（跟随系统/深色/浅色）与主题色彩（预设色 + 自定义）两组设置，
/// 选择后全局即时生效并持久化保存
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

  /// 预设主题色彩列表；首位为默认品牌紫
  static const List<Color> _presetColors = [
    AppPalette.brandPrimary,
    Color(0xFF3D8BFF),
    Color(0xFF1FB6C9),
    Color(0xFF2FBF71),
    Color(0xFFF5A623),
    Color(0xFFFF7A45),
    Color(0xFFF25555),
    Color(0xFFE85D9E),
  ];

  @override
  Widget build(BuildContext context) {
    // InheritedNotifier 依赖：主题状态变化时本页自动重建，选中态即时刷新
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
                          _buildModeCard(context, controller),
                          const SizedBox(height: 14),
                          _buildColorCard(context, controller),
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

  /// 「主题模式」分组卡片
  Widget _buildModeCard(
    BuildContext context,
    ThemeController controller,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surfaceBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '主题模式',
            style: TextStyle(
              color: context.palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          for (final option in _options)
            _ModeOption(
              data: option,
              selected: controller.mode == option.mode,
              onTap: () => controller.setMode(option.mode),
            ),
        ],
      ),
    );
  }

  /// 「主题色彩」分组卡片：预设色板 + 自定义入口
  Widget _buildColorCard(
    BuildContext context,
    ThemeController controller,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surfaceBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '主题色彩',
            style: TextStyle(
              color: context.palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '选择强调色，深浅主题下同步生效',
            style: TextStyle(
              color: context.palette.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final color in _presetColors)
                _PresetSwatch(
                  color: color,
                  selected: controller.seedColor == color,
                  onTap: () => controller.setSeedColor(color),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _CustomColorTile(
            currentColor: controller.seedColor,
            // 当前色为预设色时自定义入口不标选中，避免两个位置同时高亮
            selected: !_presetColors.contains(controller.seedColor),
            onTap: () async {
              final picked = await showColorPickerDialog(
                context,
                initialColor: controller.seedColor,
              );
              // 弹窗可能比页面存活更久，使用前需确认页面仍在树内
              if (picked != null && context.mounted) {
                await controller.setSeedColor(picked);
              }
            },
          ),
        ],
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

/// 预设色块：圆形色样，选中态外圈描边 + 白色对勾
class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;

  /// 是否为当前生效色彩
  final bool selected;

  /// 点击回调
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        // 以色值构造 key，便于测试按颜色定位色块
        key: ValueKey('preset_swatch_${colorToHex(color)}'),
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          // 选中态以同色描边点亮外圈，未选中用调色板描边弱化
          border: Border.all(
            width: 2.5,
            color: selected ? color : context.palette.stroke,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
            : null,
      ),
    );
  }
}

/// 自定义颜色入口行：当前颜色块 + 标题 + 色值 + 箭头
class _CustomColorTile extends StatelessWidget {
  const _CustomColorTile({
    required this.currentColor,
    required this.selected,
    required this.onTap,
  });

  /// 当前生效颜色（展示于左侧色块与右侧色值）
  final Color currentColor;

  /// 当前颜色是否来自自定义（非预设色时高亮本入口）
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          // 与模式选项行一致：选中态品牌描边 + 淡底
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
                // 调色板图标容器：淡品牌底承载当前颜色块，示意「可调色」
                color: palette.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.tune_rounded,
                size: 20,
                color: currentColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                '自定义颜色',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              colorToHex(currentColor),
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12.5,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: palette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
