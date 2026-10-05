import 'package:flutter/material.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';
import 'package:horyx/shared/widgets/lan_mode_panel.dart';
import 'package:horyx/shared/widgets/option_block.dart';
import 'package:horyx/shared/widgets/option_panel.dart';
import 'package:horyx/shared/widgets/primary_button.dart';
import 'package:horyx/shared/widgets/resume_card.dart';
import 'package:horyx/shared/widgets/setup_scaffold.dart';

/// 飞行棋 - 对局设置视图
/// 顶部展示未完成对局的恢复入口（存在存档时），
/// 下方为对局模式选择（本地/局域网）与人数输入、开始/创建房间按钮
class AeroplaneSetupView extends StatefulWidget {
  const AeroplaneSetupView({
    super.key,
    required this.onStart,
    required this.onCreateRoom,
    this.savedState,
    this.onResume,
  });

  /// 点击「开始对局」回调（本地模式），参数为所选人数
  final ValueChanged<int> onStart;

  /// 局域网模式点击「创建房间」回调，参数为房间容量（2..4）
  final ValueChanged<int> onCreateRoom;

  /// 未完成对局的存档；null 时不显示恢复入口
  final AeroplaneGameState? savedState;

  /// 点击「继续上次对局」回调
  final VoidCallback? onResume;

  /// 可选人数范围
  static const int minPlayers = 2;
  static const int maxPlayers = 4;

  @override
  State<AeroplaneSetupView> createState() => _AeroplaneSetupViewState();
}

class _AeroplaneSetupViewState extends State<AeroplaneSetupView> {
  /// 当前生效人数：输入合法值时即时更新，开始/创建房间时上报；
  /// 非法输入（如超范围）保持上次生效值，与红边提示语义一致
  late int _playerCount;

  /// 人数输入控制器（初始预填当前人数，需在 dispose 释放）
  late final TextEditingController _playersController;

  /// 输入焦点（聚焦时主题色描边提示输入中）
  late final FocusNode _playersFocus;

  /// 是否选择局域网模式；默认本地对弈
  bool _isLan = false;

  @override
  void initState() {
    super.initState();
    _playerCount = AeroplaneSetupView.minPlayers;
    _playersController =
        TextEditingController(text: '${AeroplaneSetupView.minPlayers}');
    _playersFocus = FocusNode();
  }

  @override
  void dispose() {
    _playersController.dispose();
    _playersFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.savedState;

    // 人数为输入框，键盘弹出会压缩可用高度，启用滚动避免溢出
    // （Flutter 会自动滚动让聚焦的输入框可见）
    return SetupScaffold(
      scrollable: true,
      children: [
        // 存在未完成对局时展示恢复入口
        if (saved != null) ...[
          ResumeCard(
            onTap: widget.onResume,
          ),
          const SizedBox(height: 16),
        ],
        LanModePanel(
          isLan: _isLan,
          onChanged: (v) => setState(() => _isLan = v),
          description:
              '本地同屏轮流掷骰；局域网需各设备连接同一 Wi-Fi（或一方开热点）',
        ),
        const SizedBox(height: 16),
        OptionPanel(
          title: '参与人数',
          description:
              '输入参与人数（${AeroplaneSetupView.minPlayers}-${AeroplaneSetupView.maxPlayers}），'
              '按座位顺序轮流行动',
          child: NumberOptionBlock(
            controller: _playersController,
            focusNode: _playersFocus,
            hintText:
                '${AeroplaneSetupView.minPlayers}-${AeroplaneSetupView.maxPlayers}',
            min: AeroplaneSetupView.minPlayers,
            max: AeroplaneSetupView.maxPlayers,
            defaultValue: AeroplaneSetupView.minPlayers,
            onValid: (v) => _playerCount = v,
            // 清空输入回退默认人数
            onCleared: () => _playerCount = AeroplaneSetupView.minPlayers,
          ),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          // 局域网模式按钮变为「创建房间」，进入房间等待页（自己为玩家 1）
          label: _isLan ? '创建房间' : '开始对局',
          icon: _isLan
              ? Icons.wifi_tethering_rounded
              : Icons.local_fire_department_rounded,
          onPressed: _isLan
              ? () => widget.onCreateRoom(_playerCount)
              : () => widget.onStart(_playerCount),
        ),
      ],
    );
  }
}
