import 'package:flutter/material.dart';

import 'package:horyx/shared/theme/app_theme.dart';

/// 通用弹窗容器：透明 Dialog + 统一卡片样式（surfaceBg 底 + 圆角 24 + 描边）
/// 确认弹窗/终局弹窗/更新弹窗/颜色选择器共用，容器样式只在此一处维护。
/// 内置横屏限宽（maxWidth 400）：横屏时可用宽度是整个屏幕宽，内容 stretch
/// 会把弹窗拉成一条长横幅，观感很差（曾因复制遗漏导致颜色选择器横屏拉长）
class DialogShell extends StatelessWidget {
  const DialogShell({super.key, required this.child});

  /// 弹窗内容
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      // 限制最大宽度：竖屏手机宽度本就小于该值不受影响，横屏防拉长
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: palette.surfaceBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: palette.stroke),
          ),
          child: child,
        ),
      ),
    );
  }
}
