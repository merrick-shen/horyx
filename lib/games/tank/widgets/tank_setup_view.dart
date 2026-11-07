import 'package:flutter/material.dart';

import 'package:horyx/games/tank/models/tank_game_state.dart';
import 'package:horyx/shared/widgets/lan_mode_setup.dart';
import 'package:horyx/shared/widgets/resume_card.dart';
import 'package:horyx/shared/widgets/setup_scaffold.dart';

/// 坦克动荡 - 对局模式设置视图
/// 提供对局模式选择（本地/局域网）；存在未完成存档时
/// 在顶部展示「继续上次对战」恢复入口（仅恢复比分）
class TankSetupView extends StatelessWidget {
  const TankSetupView({
    super.key,
    required this.savedState,
    required this.onResume,
    required this.onStart,
    required this.onCreateRoom,
  });

  /// 未完成存档（非空时展示「继续上次对战」恢复入口）
  final TankGameState? savedState;

  /// 点击恢复入口回调（页面从存档恢复比分进入对局）
  final VoidCallback onResume;

  /// 点击「开始对战」回调（本地模式）
  final VoidCallback onStart;

  /// 局域网模式点击「创建房间」回调
  final VoidCallback onCreateRoom;

  @override
  Widget build(BuildContext context) {
    final saved = savedState;

    return SetupScaffold(
      children: [
        // 未完成存档恢复入口：摘要与存档管理页文案保持一致
        if (saved != null) ...[
          ResumeCard(
            title: '继续上次对战',
            onTap: onResume,
          ),
          const SizedBox(height: 24),
        ],
        LanModeSetup(
          description:
              '本地同屏对战；局域网需两台设备连接同一 Wi-Fi（或一方开热点）',
          startLabel: '开始对战',
          onStart: onStart,
          onCreateRoom: onCreateRoom,
        ),
      ],
    );
  }
}
