import 'package:flutter/material.dart';

import '../models/game_info.dart';
import '../pages/games/gomoku_online_page.dart';
import '../pages/games/gomoku_page.dart';
import '../pages/games/scoreboard_page.dart';
import '../pages/games/weiqi_page.dart';
import '../pages/games/word_pk_online_page.dart';
import '../pages/games/word_pk_page.dart';

/// 游戏注册中心：所有游戏的单一事实来源
/// 新增/恢复游戏只需在此登记一处，首页入口、房间图标与
/// 客户端联机跳转均自动生效（无需再改各 UI 层的硬编码映射）
abstract final class GameData {
  /// 单词PK
  static final GameInfo wordPk = GameInfo(
    name: '单词PK',
    description: '轮流拼写英文单词，考验词汇量的回合对决',
    icon: Icons.spellcheck_rounded,
    pageBuilder: (context) => const WordPkPage(),
    onlineClientBuilder: (context, client) =>
        WordPkOnlinePage.client(client: client),
  );

  /// 五子棋
  static final GameInfo gomoku = GameInfo(
    name: '五子棋',
    description: '黑白轮流落子，先连成五子者胜',
    icon: Icons.grid_on_rounded,
    pageBuilder: (context) => const GomokuPage(),
    onlineClientBuilder: (context, client) =>
        GomokuOnlinePage.client(client: client),
  );

  /// 围棋
  /// 暂时下架：不在 [games] 列表中即不展示首页入口，页面与规则代码保留；
  /// 恢复时把 weiqi 加回 [games] 列表即可（入口跳转随注册表自动恢复）
  static final GameInfo weiqi = GameInfo(
    name: '围棋',
    description: '黑白围地博弈，气尽提子，地多者胜',
    icon: Icons.blur_on_rounded,
    pageBuilder: (context) => const WeiqiPage(),
  );

  /// 计分器（纯本地工具，无联机对局页）
  static final GameInfo scoreboard = GameInfo(
    name: '计分器',
    description: '运动计分板，支持主流运动项目',
    icon: Icons.score_rounded,
    pageBuilder: (context) => const ScoreboardPage(),
  );

  /// 全部已注册游戏（含暂时下架的围棋）
  /// 按名称查找必须覆盖全量：老版本 App 创建的房间在下架后仍可能被房间列表发现
  static final List<GameInfo> _registered = [
    wordPk,
    gomoku,
    weiqi,
    scoreboard,
  ];

  /// 首页游戏列表（围棋暂时下架，恢复时把 weiqi 加回列表即可）
  static final List<GameInfo> games = [
    wordPk,
    gomoku,
    scoreboard,
  ];

  /// 按名称查找游戏（含下架游戏）；未登记返回 null
  static GameInfo? byName(String name) {
    for (final game in _registered) {
      if (game.name == name) return game;
    }
    return null;
  }

  /// 按名称取游戏图标（未登记的游戏回退通用图标）
  /// 房间列表卡片与房间等待页共用，避免各自维护名称匹配
  static IconData iconFor(String name) =>
      byName(name)?.icon ?? Icons.sports_esports_rounded;
}
