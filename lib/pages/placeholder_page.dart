import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/app_top_bar.dart';

/// 通用占位页
/// 功能待开发的页面统一使用：顶栏 + 居中「功能开发中」提示
/// 后续功能就绪时替换为各自的正式页面
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title, this.icon});

  /// 顶栏标题
  final String title;

  /// 占位提示图标，默认问号
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    // push 进入的页面不在 AppShell 树内，需自行处理状态栏样式
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppTopBar(
                title: title,
                leading: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: AppColors.textPrimary,
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
                        color: AppColors.textSecondary,
                        size: 36,
                      ),
                      SizedBox(height: 12),
                      Text(
                        '功能开发中，敬请期待',
                        style: TextStyle(
                          color: AppColors.textSecondary,
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
      ),
    );
  }
}
