import 'package:flutter/material.dart';

import '../../models/games/weiqi_game_state.dart';
import '../../theme/app_theme.dart';
import '../common/option_block.dart';
import '../common/panel_card.dart';
import '../common/primary_button.dart';
import '../common/resume_card.dart';

/// 围棋 - 规格设置视图
/// 顶部展示未完成对局的恢复入口（存在存档时），
/// 下方为棋盘规格选择与开始按钮
class WeiqiSetupView extends StatelessWidget {
  const WeiqiSetupView({
    super.key,
    required this.boardSize,
    required this.onSelect,
    required this.onStart,
    this.savedState,
    this.onResume,
  });

  /// 当前选中路数
  final int boardSize;

  /// 选择规格回调
  final ValueChanged<int> onSelect;

  /// 点击「开始对局」回调
  final VoidCallback onStart;

  /// 未完成对局的存档；null 时不显示恢复入口
  final WeiqiGameState? savedState;

  /// 点击「继续上次对局」回调
  final VoidCallback? onResume;

  /// 可选规格：9 路小盘 / 13 路中盘 / 19 路标准盘
  static const List<(int, String)> _options = [
    (9, '9×9'),
    (13, '13×13'),
    (19, '19×19'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final saved = savedState;

    return SizedBox.expand(
      child: Center(
        // 平板/桌面端限制内容宽度，居中展示
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 存在未完成对局时展示恢复入口
                if (saved != null) ...[
                  ResumeCard(
                    summary:
                        '${saved.boardSize}×${saved.boardSize} 对局 · '
                        '已下 ${saved.moves.length} 手',
                    onTap: onResume,
                  ),
                  const SizedBox(height: 16),
                ],
                PanelCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '棋盘规格',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '9 路小盘节奏轻快，13 路攻防均衡，19 路为标准对局盘',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final (size, label) in _options)
                            OptionBlock(
                              label: label,
                              selected: size == boardSize,
                              onTap: () => onSelect(size),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: '开始对局',
                  icon: Icons.sports_esports_rounded,
                  onPressed: onStart,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
