import 'package:flutter/material.dart';

import '../../models/games/word_pk_game_state.dart';
import '../../theme/app_theme.dart';
import '../common/option_block.dart';
import '../common/panel_card.dart';
import '../common/primary_button.dart';
import '../common/resume_card.dart';

/// 单词PK - 人数设置视图
/// 顶部展示未完成对局的恢复入口（存在存档时），
/// 下方为对局模式选择（本地/局域网）、人数选择与开始按钮
class WordPkSetupView extends StatefulWidget {
  const WordPkSetupView({
    super.key,
    required this.onStart,
    required this.onCreateRoom,
    this.savedState,
    this.onResume,
  });

  /// 点击「开始 PK」回调，参数为所选人数（本地模式）
  final ValueChanged<int> onStart;

  /// 局域网模式点击「创建房间」回调，参数为所选总人数
  final ValueChanged<int> onCreateRoom;

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

  /// 是否选择局域网模式；默认本地对战（与现有同屏玩法一致）
  /// 联机人数可选 2-8 人：创建者固定为玩家 1，其余玩家通过加入房间依次入座
  bool _isLan = false;

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
                  ResumeCard(
                    summary:
                        '${saved.playerCount} 人对局 · '
                        '已验证 ${saved.entries.length} 个单词',
                    onTap: widget.onResume,
                  ),
                  const SizedBox(height: 16),
                ],
                // 对局模式选择面板
                PanelCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '对局模式',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '本地同屏轮流输入；局域网需两台设备连接同一 Wi-Fi（或一方开热点）',
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
                          OptionBlock(
                            label: '本地对战',
                            selected: !_isLan,
                            onTap: () => setState(() => _isLan = false),
                          ),
                          OptionBlock(
                            label: '局域网对战',
                            selected: _isLan,
                            onTap: () => setState(() => _isLan = true),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
                  // 局域网模式按钮变为「创建房间」，进入房间等待页（自己为玩家 1）
                  label: _isLan ? '创建房间' : '开始 PK',
                  icon: _isLan
                      ? Icons.wifi_tethering_rounded
                      : Icons.local_fire_department_rounded,
                  onPressed: _isLan
                      ? () => widget.onCreateRoom(_selected)
                      : () => widget.onStart(_selected),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
