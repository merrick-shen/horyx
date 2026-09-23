import 'package:flutter/material.dart';

import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/storage/archive_storage.dart';

/// 存档管理页的接入适配（GameRegistry 登记时挂接；null 表示不参与存档管理）。
/// 摘要/保存时间由各游戏存档模型实现 [GameArchiveSummary] 契约提供，
/// 新增游戏只需在注册表登记一处，存档管理页自动生效
class GameArchiveInfo {
  const GameArchiveInfo({required this.load, required this.clear});

  /// 读取该游戏未完成存档；无存档返回 null
  /// （直接转发对应 ArchiveStorage.load，模型已实现展示契约）
  final Future<GameArchiveSummary?> Function() load;

  /// 清除该游戏存档（存档管理页删除按钮用）
  final Future<void> Function() clear;
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
