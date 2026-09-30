import 'package:flutter/material.dart';

import 'package:horyx/games/tank/models/tank_game_state.dart';
import 'package:horyx/games/tank/pages/tank_battle_page.dart';
import 'package:horyx/games/tank/pages/tank_online_page.dart';
import 'package:horyx/games/tank/services/tank_storage.dart';
import 'package:horyx/games/tank/widgets/tank_setup_view.dart';
import 'package:horyx/shared/pages/room_page.dart';
import 'package:horyx/shared/profile/profile_controller.dart';
import 'package:horyx/shared/storage/archive_storage.dart';
import 'package:horyx/shared/storage/game_archive_state.dart';
import 'package:horyx/shared/widgets/app_top_bar.dart';

/// 坦克动荡游戏页
/// 设置视图提供对局模式选择（本地/局域网）：本地对战进入横屏对局页；
/// 局域网创建房间满员后跳转联机对局页（房主 = 红方）
/// 状态栏样式由 MaterialApp 的 builder 统一处理（随主题亮度变化）
/// 存档仅保存双方比分（战场状态不保存）：退出对局时询问保存，
/// 存在存档时设置视图展示「继续上次对战」恢复入口
class TankPage extends StatefulWidget {
  const TankPage({super.key});

  /// 联机房间标识名：GameRegistry 登记、建房入口与房间标识卡共用的
  /// 单一事实来源（注册数据归游戏模块自身，注册中心只做汇总）
  static const String gameName = '坦克动荡';

  /// 游戏图标：与 [gameName] 同为注册数据的单一来源
  static const IconData gameIcon = Icons.gps_fixed_rounded;

  @override
  State<TankPage> createState() => _TankPageState();
}

class _TankPageState
    extends GameArchiveStateBase<TankPage, TankGameState> {
  @override
  ArchiveStorage<TankGameState> get archiveStorage => TankStorage.instance;

  // 坦克设置页始终处于"设置阶段"：本页没有对局内状态，
  // 仅需在进入/从对局页返回时检测存档刷新恢复入口
  @override
  bool get isInSetupPhase => true;

  @override
  void initState() {
    super.initState();
    loadSavedState();
  }

  /// 进入对局页（开始新对战或恢复存档），返回后刷新恢复入口：
  /// 保存退出后需展示新存档；不保存退出后存档已清，入口应消失
  Future<void> _openBattle({TankGameState? saved}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TankBattlePage(
          initialRedScore: saved?.redScore ?? 0,
          initialGreenScore: saved?.greenScore ?? 0,
        ),
      ),
    );
    if (mounted) loadSavedState();
  }

  /// 开始本地对战：进入横屏对局页（新对局 0:0 起步）
  void _onStart() => _openBattle();

  /// 恢复未完成对战：从存档比分继续累计
  void _resumeSaved() {
    final saved = savedState;
    if (saved == null) return;
    _openBattle(saved: saved);
  }

  /// 局域网模式：创建房间并进入等待页（固定 2 人，自己为玩家 1）；
  /// 满员开局后跳转联机对局页接管房间（本页 = 房主 = 红方）
  Future<void> _createRoom() async {
    if (!await ensureProfileForOnline(context)) return;
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomPage.host(
          gameName: TankPage.gameName,
          hostName: ProfileScope.of(context).name,
          icon: TankPage.gameIcon,
          capacity: 2,
          hostGameBuilder: (context, host) =>
              TankOnlinePage.host(host: host),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // 顶部由 AppTopBar 自行吸收状态栏（表面色整体延伸），此处不再避让
        top: false,
        bottom: false,
        child: Column(
          children: [
            AppTopBar(
              title: '坦克动荡',
              showBack: true,
            ),
            Expanded(
              child: TankSetupView(
                savedState: savedState,
                onResume: _resumeSaved,
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
