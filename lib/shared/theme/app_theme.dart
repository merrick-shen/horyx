import 'package:flutter/material.dart';

/// 全局调色板：随主题（深/浅）变化的语义化颜色集合
/// 通过 ThemeExtension 注入 ThemeData，组件统一经 context.palette 取用，
/// 同一套组件代码即可在两种主题下自动适配，避免色值散落与硬编码
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.scaffoldBg,
    required this.surfaceBg,
    required this.surfaceHover,
    required this.stroke,
    required this.textPrimary,
    required this.textSecondary,
    required this.primary,
  });

  /// 页面背景
  final Color scaffoldBg;

  /// 卡片 / 容器背景
  final Color surfaceBg;

  /// 悬停态容器背景（比默认背景略亮，强化反馈）
  final Color surfaceHover;

  /// 描边 / 分隔线
  final Color stroke;

  /// 主文字
  final Color textPrimary;

  /// 次要文字（描述、辅助信息）
  final Color textSecondary;

  /// 品牌强调色（UI 统一使用纯色，不使用渐变；深浅主题共用同一强调色）
  final Color primary;

  /// 默认品牌紫：未自定义主题色彩时的强调色
  static const Color brandPrimary = Color(0xFF7C5CFF);

  /// 深色调色板：纯黑背景
  static const AppPalette dark = AppPalette(
    scaffoldBg: Color(0xFF000000),
    surfaceBg: Color(0xFF141C33),
    surfaceHover: Color(0xFF1A2442),
    stroke: Color(0xFF263253),
    textPrimary: Color(0xFFF3F6FF),
    textSecondary: Color(0xFF94A0C4),
    primary: brandPrimary,
  );

  /// 浅色调色板：冷白底 + 淡紫灰层次，保持品牌紫强调色
  static const AppPalette light = AppPalette(
    scaffoldBg: Color(0xFFF4F5FA),
    surfaceBg: Color(0xFFFFFFFF),
    surfaceHover: Color(0xFFEDEFF7),
    stroke: Color(0xFFE2E5F0),
    textPrimary: Color(0xFF1B2136),
    textSecondary: Color(0xFF5C6684),
    primary: brandPrimary,
  );

  /// 以指定强调色生成深色调色板（用户自定义主题色彩时使用）
  static AppPalette darkOf(Color primary) => dark.copyWith(primary: primary);

  /// 以指定强调色生成浅色调色板（用户自定义主题色彩时使用）
  static AppPalette lightOf(Color primary) => light.copyWith(primary: primary);

  @override
  AppPalette copyWith({
    Color? scaffoldBg,
    Color? surfaceBg,
    Color? surfaceHover,
    Color? stroke,
    Color? textPrimary,
    Color? textSecondary,
    Color? primary,
  }) {
    return AppPalette(
      scaffoldBg: scaffoldBg ?? this.scaffoldBg,
      surfaceBg: surfaceBg ?? this.surfaceBg,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      stroke: stroke ?? this.stroke,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      primary: primary ?? this.primary,
    );
  }

  /// 主题切换动画期间由框架调用，对两组调色板做颜色插值
  @override
  AppPalette lerp(covariant ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      scaffoldBg: Color.lerp(scaffoldBg, other.scaffoldBg, t)!,
      surfaceBg: Color.lerp(surfaceBg, other.surfaceBg, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      stroke: Color.lerp(stroke, other.stroke, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
    );
  }
}

/// 便捷取色扩展：任意 build 上下文中通过 context.palette 拿到当前主题调色板
extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

/// 颜色转 #RRGGBB 大写文本（主题色彩的展示格式）
String colorToHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

/// 全局主题配置：深浅两套主题共用一套构建逻辑，仅调色板与亮度不同
/// 强调色（primary）由用户选择的主题色彩决定，构建时动态注入
abstract final class AppTheme {
  static ThemeData darkOf(Color primary) =>
      _build(Brightness.dark, AppPalette.darkOf(primary));
  static ThemeData lightOf(Color primary) =>
      _build(Brightness.light, AppPalette.lightOf(primary));

  static ThemeData _build(Brightness brightness, AppPalette palette) =>
      ThemeData(
        useMaterial3: true,
        brightness: brightness,
        scaffoldBackgroundColor: palette.scaffoldBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: palette.primary,
          brightness: brightness,
        ),
        // 注入调色板，组件侧经 context.palette 读取
        extensions: [palette],
        // 底部导航栏配色与主页统一：
        // M3 默认背景取 colorScheme.surfaceContainer（偏灰），需覆盖为页面背景色
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: palette.scaffoldBg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          indicatorColor: palette.primary.withValues(alpha: 0.25),
          height: 68,
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              size: 24,
              // 选中用品牌紫，未选中用次要文字色
              color: selected ? palette.primary : palette.textSecondary,
            );
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? palette.textPrimary : palette.textSecondary,
            );
          }),
        ),
      );
}
