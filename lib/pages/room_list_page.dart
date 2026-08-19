import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/primary_button.dart';
import 'placeholder_page.dart';

/// 局域网房间列表页（底部导航「联机」tab 常驻页）
/// 展示同一局域网内可加入的房间（游戏、房主、当前人数）：
/// - 有房间时展示房间卡片列表，每项提供「加入房间」按钮
/// - 无房间时整页切换为空状态提示
/// 当前为静态结构阶段：列表为演示数据，房间发现与加入交互待联机里程碑接入
/// 状态栏样式与底部导航由外层 AppShell 统一管理
class RoomListPage extends StatelessWidget {
  const RoomListPage({super.key});

  /// 静态演示数据：模拟局域网内已创建的房间（含一个满员房间）
  /// 接入房间发现（UDP 广播）后由实时数据替换；清空此列表可预览空状态
  static const List<_RoomInfo> _demoRooms = [
    _RoomInfo(game: '五子棋', host: '小明', currentPlayers: 1, maxPlayers: 2),
    _RoomInfo(game: '围棋', host: '小红', currentPlayers: 2, maxPlayers: 2),
    _RoomInfo(game: '五子棋', host: '阿伟', currentPlayers: 1, maxPlayers: 2),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // tab 常驻页无返回入口（与首页一致），仅展示标题
            const AppTopBar(title: '房间列表'),
            Expanded(
              // 列表为空时整页切换为空状态提示
              child: _demoRooms.isEmpty
                  ? const _EmptyView()
                  : SizedBox.expand(
                      child: Center(
                        // 平板/桌面端限制内容宽度，居中展示
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
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
                                    color: palette.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: ListView.separated(
                                  padding: const EdgeInsets.all(20),
                                  itemCount: _demoRooms.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 14),
                                  itemBuilder: (context, index) => _RoomCard(
                                    room: _demoRooms[index],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 房间信息：静态结构阶段的演示数据模型
/// 字段对齐房间展示需求（游戏、创建者、当前人数）；
/// 接入局域网房间发现后由网络层提供的真实房间数据替换
class _RoomInfo {
  const _RoomInfo({
    required this.game,
    required this.host,
    required this.currentPlayers,
    required this.maxPlayers,
  });

  /// 房间对应的游戏名称（如「五子棋」「围棋」）
  final String game;

  /// 创建者（房主）昵称
  final String host;

  /// 当前房间人数
  final int currentPlayers;

  /// 房间人数上限
  final int maxPlayers;

  /// 是否已满员（满员后不可加入）
  bool get isFull => currentPlayers >= maxPlayers;
}

/// 房间卡片：游戏名 + 房主/人数信息 + 「加入房间」按钮
/// 满员房间的加入按钮置为禁用态（灰底不可点击）
class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room});

  /// 卡片展示的房间信息
  final _RoomInfo room;

  /// 加入房间：静态结构阶段联机对局页未开发，暂以占位页承接
  void _join(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PlaceholderPage(title: '联机对局'),
      ),
    );
  }

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
          // 房间图标
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.wifi_tethering_rounded,
              color: palette.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          // 房间信息：游戏名主行 + 房主与人数副行
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.game,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '房主：${room.host} · ${room.currentPlayers}/${room.maxPlayers} 人',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 固定宽度槽位：「已满员」比「加入房间」短且无图标，
          // 不固定宽度时两种状态按钮宽窄不一，列表扫视不齐
          SizedBox(
            width: 128,
            child: PrimaryButton(
              label: room.isFull ? '已满员' : '加入房间',
              // 满员时禁用（灰底不可点击），其余房间可加入
              onPressed: room.isFull ? null : () => _join(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// 空状态视图：局域网内暂无可加入房间时的整页提示
/// 布局与通用占位页一致（图标 + 主提示 + 辅助说明）
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
