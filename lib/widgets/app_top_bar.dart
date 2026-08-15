import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 应用通用顶栏：居中标题 + 底部描边
/// 主页与游戏页共用，保证视觉统一
class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key, required this.title, this.leading});

  /// 顶栏标题文字
  final String title;

  /// 可选的前置控件（如游戏页的返回按钮）
  /// 使用 Stack 绝对居中，标题不因前置控件而偏移
  final Widget? leading;

  static const double _height = 64;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.scaffoldBg,
        // 底部描边让顶栏与内容区分层
        border: Border(bottom: BorderSide(color: context.palette.stroke)),
      ),
      child: SizedBox(
        height: _height,
        child: Stack(
          children: [
            Center(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: context.palette.primary,
                ),
              ),
            ),
            if (leading != null)
              Align(alignment: Alignment.centerLeft, child: leading!),
          ],
        ),
      ),
    );
  }
}
