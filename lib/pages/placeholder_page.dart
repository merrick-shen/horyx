import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_top_bar.dart';

/// 通用占位页
/// 功能待开发的页面统一使用：顶栏 + 居中「功能开发中」提示
/// 后续功能就绪时替换为各自的正式页面
/// 状态栏样式由 MaterialApp 的 builder 统一处理（随主题亮度变化）
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title, this.icon});

  /// 顶栏标题
  final String title;

  /// 占位提示图标，默认问号
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppTopBar(
              title: title,
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
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      // 未指定图标时使用默认问号
                      icon ?? Icons.help_outline_rounded,
                      color: context.palette.textSecondary,
                      size: 36,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '功能开发中，敬请期待',
                      style: TextStyle(
                        color: context.palette.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
