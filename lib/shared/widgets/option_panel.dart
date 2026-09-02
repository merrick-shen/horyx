import 'package:flutter/material.dart';

import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/widgets/panel_card.dart';

/// 通用设置面板：标题 + 说明 + 设置项主体
/// 各游戏 setup_view 与 LanModePanel 共用，统一
/// 「标题 16/w700 + 说明 13 + 间距 18 + 内容」的结构（原先各视图内联重复实现）
class OptionPanel extends StatelessWidget {
  const OptionPanel({
    super.key,
    required this.title,
    required this.description,
    required this.child,
  });

  /// 面板标题（如「棋盘规格」「对局模式」）
  final String title;

  /// 面板说明文字；各游戏玩法不同，文案由调用方提供
  final String description;

  /// 面板主体：通常为 Wrap(OptionBlock) 或数字输入块
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}
