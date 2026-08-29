import 'package:flutter/material.dart';

import 'package:horyx/shared/game/game_data.dart';
import 'package:horyx/games/tank/widgets/tank_setup_view.dart';
import 'package:horyx/shared/network/room_page.dart';
import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/widgets/app_top_bar.dart';

/// 坦克动荡游戏页
/// 当前为骨架阶段：设置视图提供对局模式选择（本地/局域网），
/// 对局视图暂为空白占位，游戏玩法后续实现
/// 状态栏样式由 MaterialApp 的 builder 统一处理（随主题亮度变化）
class TankPage extends StatefulWidget {
  const TankPage({super.key});

  @override
  State<TankPage> createState() => _TankPageState();
}

class _TankPageState extends State<TankPage> {
  /// 是否已开始对局（false = 对局模式设置阶段）
  bool _started = false;

  /// 开始本地对战：进入对局视图（玩法暂未实现，先展示占位）
  void _onStart() {
    setState(() => _started = true);
  }

  /// 局域网模式：创建房间并进入等待页（固定 2 人，自己为玩家 1）
  /// 联机对局页尚未接入：满员后停留在等待页「即将开始」过渡态
  void _createRoom() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomPage.host(
          gameName: GameData.tank.name,
          capacity: 2,
        ),
      ),
    );
  }

  /// 回到设置视图（对局视图暂无对局内容，退出无需确认）
  void _backToSetup() {
    setState(() => _started = false);
  }

  /// 退出请求：设置阶段直接退出页面，对局阶段回设置视图
  void _requestExit() {
    if (!_started) {
      Navigator.of(context).pop();
      return;
    }
    _backToSetup();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 对局阶段拦截系统返回（回设置视图），设置阶段允许直接返回
      canPop: !_started,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToSetup();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppTopBar(
                title: '坦克动荡',
                showBack: true,
                onBack: _requestExit,
              ),
              Expanded(
                // 阶段切换动画：设置视图 <-> 对局视图（暂为空白占位）
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _started
                      ? _buildGamePlaceholder()
                      : TankSetupView(
                          key: const ValueKey('setup'),
                          onStart: _onStart,
                          onCreateRoom: _createRoom,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 对局视图占位：玩法实现前的空白展示
  Widget _buildGamePlaceholder() {
    return Center(
      child: Text(
        '对局页面开发中',
        style: TextStyle(
          color: context.palette.textSecondary,
          fontSize: 14,
        ),
      ),
    );
  }
}
