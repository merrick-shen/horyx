import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 应用通用顶栏：居中标题 + 底部描边
/// 主页与游戏页共用，保证视觉统一
class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.showBack = false,
    this.onBack,
  });

  /// 顶栏标题文字
  final String title;

  /// 是否显示返回按钮（二级页面通用样式）
  final bool showBack;

  /// 返回按钮回调；缺省时执行 maybePop。
  /// 需要退出确认流程的页面（如对局中防误触退出）传入自定义回调
  final VoidCallback? onBack;

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
            // 使用 Stack 绝对居中，标题不因返回按钮而偏移
            if (showBack)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: context.palette.textPrimary,
                    size: 20,
                  ),
                  onPressed:
                      onBack ?? () => Navigator.of(context).maybePop(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
