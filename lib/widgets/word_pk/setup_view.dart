import 'package:flutter/material.dart';

import '../../models/word_pk_game_state.dart';
import '../../theme/app_theme.dart';
import '../option_block.dart';
import '../panel_card.dart';
import '../primary_button.dart';

/// 单词PK - 人数设置视图
/// 顶部展示未完成对局的恢复入口（存在存档时），下方为人数选择与开始按钮
class WordPkSetupView extends StatefulWidget {
  const WordPkSetupView({
    super.key,
    required this.onStart,
    this.savedState,
    this.onResume,
  });

  /// 点击「开始 PK」回调，参数为所选人数
  final ValueChanged<int> onStart;

  /// 未完成对局的存档；null 时不显示恢复入口
  final WordPkGameState? savedState;

  /// 点击「继续上次对局」回调
  final VoidCallback? onResume;

  /// 可选人数范围
  static const int minPlayers = 2;
  static const int maxPlayers = 8;

  @override
  State<WordPkSetupView> createState() => _WordPkSetupViewState();
}

class _WordPkSetupViewState extends State<WordPkSetupView> {
  int _selected = WordPkSetupView.minPlayers;

  @override
  Widget build(BuildContext context) {
    final saved = widget.savedState;
    final palette = context.palette;

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
                  _ResumeCard(state: saved, onTap: widget.onResume),
                  const SizedBox(height: 16),
                ],
                // 人数选择面板
                PanelCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '参与人数',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '选择参与 PK 的人数（至少 2 人），玩家将按顺序轮流输入单词',
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
                          for (int n = WordPkSetupView.minPlayers;
                              n <= WordPkSetupView.maxPlayers;
                              n++)
                            OptionBlock(
                              label: '$n',
                              // 数字方块保持等宽排列
                              fixedWidth: 56,
                              selected: n == _selected,
                              onTap: () => setState(() => _selected = n),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: '开始 PK',
                  icon: Icons.local_fire_department_rounded,
                  onPressed: () => widget.onStart(_selected),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 继续上次对局入口卡片
class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.state, required this.onTap});

  final WordPkGameState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // 品牌色淡底 + 描边，与普通卡片区分，突出「可继续」
          color: palette.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: palette.primary.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.play_circle_fill_rounded,
              color: palette.primary,
              size: 34,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '继续上次对局',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${state.playerCount} 人对局 · 已验证 ${state.entries.length} 个单词',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: palette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
