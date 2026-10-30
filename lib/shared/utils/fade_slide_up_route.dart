import 'package:flutter/material.dart';

/// 详情页转场路由：淡入 + 轻微上滑的平滑过渡
/// 时长与曲线与底部导航切换一致（300ms easeOutCubic），保持全局动效统一
/// （更新日志详情 / 开源许可详情共用）
PageRouteBuilder<T> fadeSlideUpRoute<T extends Object?>(Widget page) =>
    PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) => page,
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
