import 'package:flutter/material.dart';

import '../services/network/room_client.dart';

/// 游戏注册项：游戏的单一事实来源
/// 除静态展示数据外，还承载「游戏 → 页面 / 联机对局页」的映射，
/// 由 [GameData] 统一登记，UI 层（首页卡片、房间列表等）不再各自硬编码跳转
class GameInfo {
  const GameInfo({
    required this.name,
    required this.description,
    required this.icon,
    this.pageBuilder,
    this.onlineClientBuilder,
  });

  /// 游戏名称（联机房间按此名称匹配，发布后不可随意更改）
  final String name;

  /// 简短游戏描述
  final String description;

  /// 展示图标
  final IconData icon;

  /// 游戏页构建器（首页卡片入口跳转用）；null 表示入口未开放
  final WidgetBuilder? pageBuilder;

  /// 客户端侧联机对局页构建器（加入房间满员开局后跳转用）
  /// null 表示该游戏联机对局未接入（等待页满员后停留「即将开始」）
  final Widget Function(BuildContext context, RoomClient client)?
      onlineClientBuilder;
}
