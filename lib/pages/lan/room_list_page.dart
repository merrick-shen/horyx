import 'package:flutter/material.dart';

import '../../data/game_data.dart';
import '../../services/network/room_discovery.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_top_bar.dart';
import '../../widgets/common/primary_button.dart';
import 'room_page.dart';

/// 局域网房间列表页（「联机」tab 常驻页）
/// 通过 UDP 广播自动发现同一局域网内的房间并实时展示；
/// 点击「加入房间」连接对应房主（连接与入座流程由房间等待页负责）
class RoomListPage extends StatefulWidget {
  const RoomListPage({super.key});

  @override
  State<RoomListPage> createState() => _RoomListPageState();
}

class _RoomListPageState extends State<RoomListPage> {
  /// 房间发现器：页面可见期间周期探测，销毁时停止
  late final RoomDiscovery _discovery;

  @override
  void initState() {
    super.initState();
    _discovery = RoomDiscovery();
    _discovery.start();
  }

  @override
  void dispose() {
    _discovery.stop();
    _discovery.dispose();
    super.dispose();
  }

  /// 加入房间：进入等待页并连接对应房主
  /// 满员后按游戏名从注册表取联机对局页构建器跳转
  /// （未接入联机的游戏构建器为 null，等待页满员后停留「即将开始」）
  void _join(DiscoveredRoom room) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomPage.client(
          address: room.ip,
          port: room.tcpPort,
          gameName: room.gameName,
          clientGameBuilder:
              GameData.byName(room.gameName)?.onlineClientBuilder,
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
            const AppTopBar(title: '房间列表'),
            Expanded(
              child: ListenableBuilder(
                listenable: _discovery,
                builder: (context, _) {
                  final rooms = _discovery.rooms;
                  // 无房间时整页切换为空状态提示
                  return rooms.isEmpty
                      ? const _EmptyView()
                      : SizedBox.expand(
                          child: Center(
                            // 平板/桌面端限制内容宽度，居中展示
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: 520,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // 列表引导文案：说明房间来源
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      20,
                                      20,
                                      0,
                                    ),
                                    child: Text(
                                      '同一 Wi-Fi 下好友创建的房间会显示在这里',
                                      style: TextStyle(
                                        color:
                                            context.palette.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.separated(
                                      padding: const EdgeInsets.all(20),
                                      itemCount: rooms.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: 14),
                                      itemBuilder: (context, index) =>
                                          _RoomCard(
                                        room: rooms[index],
                                        onJoin: () => _join(rooms[index]),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 房间卡片：游戏图标 + 游戏名/房主信息 + 「加入房间」按钮
/// 满员房间的加入按钮置为禁用态（灰底不可点击）
class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.onJoin});

  /// 卡片展示的房间信息
  final DiscoveredRoom room;

  /// 点击加入回调（满员时不会被调用）
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.stroke),
      ),
      child: Row(
        children: [
          // 游戏图标：按游戏名从注册表匹配，未匹配时回退通用图标
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              GameData.iconFor(room.gameName),
              color: palette.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          // 房间信息：游戏名主行 + 房主地址与人数副行
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.gameName,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${room.ip} · ${room.players}/${room.capacity}',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 固定宽度槽位：满员与可加入两态按钮等宽，列表视觉对齐
          SizedBox(
            width: 112,
            child: PrimaryButton(
              label: room.isFull ? '已满员' : '加入',
              // 满员时禁用（灰底不可点击），其余房间可加入
              onPressed: room.isFull ? null : onJoin,
            ),
          ),
        ],
      ),
    );
  }
}

/// 空状态视图：局域网内暂无可加入房间时的整页提示
class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.wifi_off_rounded,
            color: palette.textSecondary,
            size: 36,
          ),
          const SizedBox(height: 12),
          Text(
            '暂无可用房间',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '请确认好友已与你连接同一 Wi-Fi 并创建了房间',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
