import 'package:flutter/material.dart';

import 'package:horyx/games/chess/models/chess_game_state.dart';
import 'package:horyx/shared/widgets/lan_mode_panel.dart';
import 'package:horyx/shared/widgets/primary_button.dart';
import 'package:horyx/shared/widgets/resume_card.dart';
import 'package:horyx/shared/widgets/setup_scaffold.dart';

/// 中国象棋 - 对局模式设置视图
/// 顶部展示未完成对局的恢复入口（存在存档时），
/// 下方为对局模式选择（本地/局域网）与开始/创建房间按钮
class ChessSetupView extends StatefulWidget {
  const ChessSetupView({
    super.key,
    required this.onStart,
    required this.onCreateRoom,
    this.savedState,
    this.onResume,
  });

  /// 点击「开始对局」回调（本地模式）
  final VoidCallback onStart;

  /// 局域网模式点击「创建房间」回调
  final VoidCallback onCreateRoom;

  /// 未完成对局的存档；null 时不显示恢复入口
  final ChessGameState? savedState;

  /// 点击「继续上次对局」回调
  final VoidCallback? onResume;

  @override
  State<ChessSetupView> createState() => _ChessSetupViewState();
}

class _ChessSetupViewState extends State<ChessSetupView> {
  /// 是否选择局域网模式；默认本地对弈
  bool _isLan = false;

  @override
  Widget build(BuildContext context) {
    final saved = widget.savedState;

    return SetupScaffold(
      children: [
        // 存在未完成对局时展示恢复入口
        if (saved != null) ...[
          ResumeCard(
            summary: saved.summary,
            onTap: widget.onResume,
          ),
          const SizedBox(height: 16),
        ],
        // 对局模式选择面板（象棋当前唯一的设置项）
        LanModePanel(
          isLan: _isLan,
          onChanged: (v) => setState(() => _isLan = v),
          description:
              '本地同屏对弈；局域网需两台设备连接同一 Wi-Fi（或一方开热点）',
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          // 局域网模式按钮变为「创建房间」，进入房间等待页（自己为玩家 1）
          label: _isLan ? '创建房间' : '开始对局',
          icon: _isLan
              ? Icons.wifi_tethering_rounded
              : Icons.local_fire_department_rounded,
          onPressed: _isLan ? widget.onCreateRoom : widget.onStart,
        ),
      ],
    );
  }
}
