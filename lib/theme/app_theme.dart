import 'package:flutter/material.dart';

/// 全局配色：深蓝黑夜色 + 紫青霓虹渐变，营造游戏氛围
/// 颜色集中定义的目的：多页面共用一套视觉规范，避免色值散落各处导致风格不统一
class AppColors {
  AppColors._();

  /// 页面背景
  static const Color scaffoldBg = Color(0xFF0B1020);

  /// 卡片 / 容器背景
  static const Color surfaceBg = Color(0xFF141C33);

  /// 悬停态容器背景（比默认背景略亮，强化反馈）
  static const Color surfaceHover = Color(0xFF1A2442);

  /// 描边 / 分隔线
  static const Color stroke = Color(0xFF263253);

  /// 主文字
  static const Color textPrimary = Color(0xFFF3F6FF);

  /// 次要文字（描述、辅助信息）
  static const Color textSecondary = Color(0xFF94A0C4);

  /// 品牌强调色
  static const Color primary = Color(0xFF7C5CFF);
  static const Color accent = Color(0xFF22D3EE);

  /// 品牌渐变（Logo、选中态等共用，保证视觉统一）
  static const List<Color> brandGradient = [primary, accent];
}

/// 全局主题配置
abstract final class AppTheme {
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.scaffoldBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ),
        // 底部导航栏配色与主页统一：
        // M3 默认背景取 colorScheme.surfaceContainer（偏灰），需覆盖为页面背景色
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.scaffoldBg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          indicatorColor: AppColors.primary.withValues(alpha: 0.25),
          height: 68,
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              size: 24,
              // 选中用品牌紫，未选中用次要文字色
              color: selected ? AppColors.primary : AppColors.textSecondary,
            );
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            );
          }),
        ),
      );
}
