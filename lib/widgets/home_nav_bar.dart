import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 顶部导航栏：品牌标识
/// 导航项待后续接入真实页面后再添加
class HomeNavBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeNavBar({super.key});

  static const double _height = 64;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.scaffoldBg,
        // 底部描边让导航栏与内容区分层
        border: Border(bottom: BorderSide(color: AppColors.stroke)),
      ),
      child: SizedBox(
        height: _height,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _Logo(),
          ),
        ),
      ),
    );
  }
}

/// 渐变文字
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    // 文字渐变需借助 ShaderMask 实现
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: AppColors.brandGradient,
      ).createShader(bounds),
      child: const Text(
        'Horyx',
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          color: Colors.white, // 会被渐变着色覆盖
        ),
      ),
    );
  }
}
