import 'package:flutter/material.dart';

import 'package:horyx/shared/widgets/lan_mode_panel.dart';
import 'package:horyx/shared/widgets/primary_button.dart';

/// 中国象棋 - 对局模式设置视图
/// 仅提供对局模式选择（本地/局域网），无其他设置项
class ChessSetupView extends StatefulWidget {
  const ChessSetupView({
    super.key,
    required this.onStart,
    required this.onCreateRoom,
  });

  /// 点击「开始对局」回调（本地模式）
  final VoidCallback onStart;

  /// 局域网模式点击「创建房间」回调
  final VoidCallback onCreateRoom;

  @override
  State<ChessSetupView> createState() => _ChessSetupViewState();
}

class _ChessSetupViewState extends State<ChessSetupView> {
  /// 是否选择局域网模式；默认本地对弈
  bool _isLan = false;

  @override
  Widget build(BuildContext context) {
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
                  onPressed:
                      _isLan ? widget.onCreateRoom : widget.onStart,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
