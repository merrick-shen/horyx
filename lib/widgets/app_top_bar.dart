import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 应用通用顶栏：居中渐变标题 + 底部描边
/// 主页与游戏页共用，保证视觉统一
class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key, required this.title});

  /// 顶栏标题文字
  final String title;

  static const double _height = 64;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.scaffoldBg,
        // 底部描边让顶栏与内容区分层
        border: Border(bottom: BorderSide(color: AppColors.stroke)),
      ),
      child: SizedBox(
        height: _height,
        child: Center(
          // 文字渐变需借助 ShaderMask 实现
          child: ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: AppColors.brandGradient,
            ).createShader(bounds),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Colors.white, // 会被渐变着色覆盖
              ),
            ),
          ),
        ),
      ),
    );
  }
}
