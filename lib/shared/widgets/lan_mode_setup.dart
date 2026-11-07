import 'package:flutter/material.dart';

import 'package:horyx/shared/widgets/lan_mode_panel.dart';
import 'package:horyx/shared/widgets/primary_button.dart';

/// 本地/局域网模式选择与主按钮组合（各游戏设置视图共用）：
/// 内部持有模式开关状态，局域网模式下主按钮切换为「创建房间」；
/// [children] 为插在模式面板与主按钮之间的游戏专属设置面板
class LanModeSetup extends StatefulWidget {
  const LanModeSetup({
    super.key,
    required this.description,
    required this.onStart,
    required this.onCreateRoom,
    this.startLabel = '开始对局',
    this.children = const [],
  });

  /// 模式面板说明文案（各游戏行动方式不同）
  final String description;

  /// 本地模式主按钮文案
  final String startLabel;

  /// 点击「开始对局」回调（本地模式）
  final VoidCallback onStart;

  /// 局域网模式点击「创建房间」回调
  final VoidCallback onCreateRoom;

  /// 游戏专属设置面板（如棋盘规格、参与人数）
  final List<Widget> children;

  @override
  State<LanModeSetup> createState() => _LanModeSetupState();
}

class _LanModeSetupState extends State<LanModeSetup> {
  /// 是否选择局域网模式；默认本地对弈
  bool _isLan = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LanModePanel(
          isLan: _isLan,
          onChanged: (v) => setState(() => _isLan = v),
          description: widget.description,
        ),
        if (widget.children.isNotEmpty) ...[
          const SizedBox(height: 16),
          ...widget.children,
        ],
        const SizedBox(height: 24),
        PrimaryButton(
          // 局域网模式按钮变为「创建房间」，进入房间等待页（自己为玩家 1）
          label: _isLan ? '创建房间' : widget.startLabel,
          icon: _isLan
              ? Icons.wifi_tethering_rounded
              : Icons.local_fire_department_rounded,
          onPressed: _isLan ? widget.onCreateRoom : widget.onStart,
        ),
      ],
    );
  }
}
