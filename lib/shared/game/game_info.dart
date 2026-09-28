import 'package:flutter/material.dart';

import 'package:horyx/shared/network/room_client.dart';

/// 存档管理页的接入适配（GameRegistry 登记时挂接；null 表示不参与存档管理）。
/// 条目列表由 ArchiveStorage.loadAllSummaries 统一读出（gameId 关联
/// GameRegistry 取名称/图标），本类只承载删除入口：
/// 按存档 id 经归属游戏的存档服务精确移除
class GameArchiveInfo {
  const GameArchiveInfo({required this.remove});

  /// 按 id 删除该游戏指定存档（存档管理页删除按钮用）
  final Future<void> Function(String id) remove;
}

/// 游戏注册项：游戏的单一事实来源
/// 除静态展示数据外，还承载「游戏 → 页面 / 联机对局页」的映射，
/// 由 GameRegistry（组合根，位于 app 层）统一登记，UI 层（首页卡片、
/// 联机页等）不再各自硬编码跳转
class GameInfo {
  const GameInfo({
    required this.name,
    required this.description,
    required this.icon,
    required this.pageBuilder,
    this.onlineClientBuilder,
    this.archive,
  });

  /// 游戏名称（联机房间按此名称匹配，发布后不可随意更改）
  final String name;

  /// 简短游戏描述
  final String description;

  /// 展示图标
  final IconData icon;

  /// 游戏页构建器（首页卡片入口跳转用）；
  /// 登记进注册表的游戏必须提供入口，不支持「入口未开放」的占位登记
  final WidgetBuilder pageBuilder;

  /// 客户端侧联机对局页构建器（加入房间满员开局后跳转用）
  /// null 表示该游戏联机对局未接入（等待页满员后停留「即将开始」）
  final Widget Function(BuildContext context, RoomClient client)?
      onlineClientBuilder;

  /// 存档管理接入（存档管理页展示名称/图标/摘要与删除清档）；
  /// null 表示该游戏不参与存档管理
  final GameArchiveInfo? archive;
}
