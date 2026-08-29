import 'package:flutter/material.dart';

import 'package:horyx/games/tank/pages/tank_battle_page.dart';
import 'package:horyx/games/tank/widgets/tank_setup_view.dart';
import 'package:horyx/shared/game/game_data.dart';
import 'package:horyx/shared/network/room_page.dart';
import 'package:horyx/shared/widgets/app_top_bar.dart';

/// 坦克动荡游戏页
/// 设置视图提供对局模式选择（本地/局域网）：本地对战进入横屏对局页；
/// 联机对局页尚未接入，满员后停留在等待页「即将开始」过渡态
/// 状态栏样式由 MaterialApp 的 builder 统一处理（随主题亮度变化）
class TankPage extends StatefulWidget {
  const TankPage({super.key});

  @override
  State<TankPage> createState() => _TankPageState();
}

class _TankPageState extends State<TankPage> {
  /// 开始本地对战：进入横屏对局页
  void _onStart() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TankBattlePage()),
    );
  }

  /// 局域网模式：创建房间并进入等待页（固定 2 人，自己为玩家 1）
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppTopBar(
              title: '坦克动荡',
              showBack: true,
            ),
            Expanded(
              child: TankSetupView(
                onStart: _onStart,
                onCreateRoom: _createRoom,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
