import 'package:flutter/material.dart';

import 'package:horyx/shared/theme/app_theme.dart';

/// 应用统一输入框装饰：圆角描边 + 主题色聚焦态
/// 填充色由调用方按所在容器选择（一般取与容器底色有对比度的表面色，
/// 如页面直铺用 surfaceBg、PanelCard 卡片内用 scaffoldBg）
InputDecoration buildAppTextFieldDecoration(
  AppPalette palette, {
  required String hintText,
  required Color fillColor,
}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(color: palette.textSecondary),
    filled: true,
    fillColor: fillColor,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 14,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.control),
      borderSide: BorderSide(color: palette.stroke),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.control),
      borderSide: BorderSide(color: palette.primary, width: 1.4),
    ),
  );
}
