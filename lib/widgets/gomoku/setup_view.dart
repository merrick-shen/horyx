import 'package:flutter/material.dart';

import '../../models/games/gomoku_game_state.dart';
import '../../theme/app_theme.dart';
import '../common/lan_mode_panel.dart';
import '../common/option_block.dart';
import '../common/panel_card.dart';
import '../common/primary_button.dart';
import '../common/resume_card.dart';

/// 五子棋 - 规格设置视图
/// 顶部展示未完成对局的恢复入口（存在存档时），
/// 下方为对局模式选择（本地/局域网）、棋盘规格选择与开始/创建房间按钮
class GomokuSetupView extends StatefulWidget {
  const GomokuSetupView({
    super.key,
    required this.boardSize,
    required this.onSelect,
    required this.onStart,
    required this.onCreateRoom,
    this.savedState,
    this.onResume,
  });

  /// 当前选中路数
  final int boardSize;

  /// 选择规格回调
  final ValueChanged<int> onSelect;

  /// 点击「开始对局」回调（本地模式）
  final VoidCallback onStart;

  /// 局域网模式点击「创建房间」回调（参数为选中路数）
  /// 联机固定 2 人对弈：创建者执黑先行，加入者执白
  final ValueChanged<int> onCreateRoom;

  /// 未完成对局的存档；null 时不显示恢复入口
  final GomokuGameState? savedState;

  /// 点击「继续上次对局」回调
  final VoidCallback? onResume;

  @override
  State<GomokuSetupView> createState() => _GomokuSetupViewState();
}

class _GomokuSetupViewState extends State<GomokuSetupView> {
  /// 是否选择局域网模式；默认本地对战（双人对弈本就同屏即可）
  bool _isLan = false;

  /// 可选规格：15 路标准盘 / 19 路大盘
  static const List<(int, String)> _options = [
    (15, '15×15'),
    (19, '19×19'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final saved = widget.savedState;

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
                        '已落子 ${saved.moves.length} 手',
                    onTap: widget.onResume,
                  ),
                  const SizedBox(height: 16),
                ],
                // 对局模式选择面板
                LanModePanel(
                  isLan: _isLan,
                  onChanged: (v) => setState(() => _isLan = v),
                  description:
                      '本地同屏对弈；局域网需两台设备连接同一 Wi-Fi（或一方开热点）',
                ),
                const SizedBox(height: 16),
                // 棋盘规格面板（本地与联机共用，联机建房沿用所选规格）
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
                        '标准 15 路棋盘节奏明快，19 路大盘空间更大、博弈更充分',
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
                              selected: size == widget.boardSize,
                              onTap: () => widget.onSelect(size),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  // 局域网模式按钮变为「创建房间」，进入房间等待页（自己执黑）
                  label: _isLan ? '创建房间' : '开始对局',
                  icon: _isLan
                      ? Icons.wifi_tethering_rounded
                      : Icons.sports_esports_rounded,
                  onPressed: _isLan
                      ? () => widget.onCreateRoom(widget.boardSize)
                      : widget.onStart,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
