import 'package:flutter/material.dart';

import 'package:horyx/shared/widgets/option_block.dart';
import 'package:horyx/shared/widgets/option_panel.dart';

/// 对局模式选择面板：本地对战 / 局域网对战二选一
///
/// 五子棋、单词PK与坦克动荡设置页共用。选中状态由调用方持有并传入：
/// 底部主按钮（开始对局/创建房间）同样依赖该状态，若面板自持状态
/// 会形成两份需同步的数据源
class LanModePanel extends StatelessWidget {
  const LanModePanel({
    super.key,
    required this.isLan,
    required this.onChanged,
    required this.description,
  });

  /// 当前是否选择局域网模式
  final bool isLan;

  /// 模式切换回调（参数为新状态）
  final ValueChanged<bool> onChanged;

  /// 面板说明文字；各游戏玩法不同（轮流输入/对弈），文案由调用方提供
  final String description;

  @override
  Widget build(BuildContext context) {
    return OptionPanel(
      title: '对局模式',
      description: description,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          OptionBlock(
            label: '本地对战',
            selected: !isLan,
            onTap: () => onChanged(false),
          ),
          OptionBlock(
            label: '局域网对战',
            selected: isLan,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}
