import 'package:flutter/material.dart';

import '../models/game_info.dart';

/// 静态游戏数据源
/// 已上线的游戏使用各自真实数据，规划中的游戏以占位页接入
abstract final class GameData {
  /// 单词PK
  static const GameInfo wordPk = GameInfo(
    name: '单词PK',
    description: '轮流拼写英文单词，考验词汇量的回合对决',
    icon: Icons.spellcheck_rounded,
  );

  /// 五子棋
  static const GameInfo gomoku = GameInfo(
    name: '五子棋',
    description: '黑白轮流落子，先连成五子者胜',
    icon: Icons.grid_on_rounded,
  );

  /// 围棋
  /// 暂时下架：不在 [games] 列表中即不展示入口，页面与规则代码保留
  static const GameInfo weiqi = GameInfo(
    name: '围棋',
    description: '黑白围地博弈，气尽提子，地多者胜',
    icon: Icons.blur_on_rounded,
  );

  /// 计分器
  static const GameInfo scoreboard = GameInfo(
    name: '计分器',
    description: '运动计分板，支持主流运动项目',
    icon: Icons.score_rounded,
  );

  /// 首页游戏列表（围棋暂时下架，恢复时把 weiqi 加回列表即可）
  static final List<GameInfo> games = [
    wordPk,
    gomoku,
    scoreboard,
  ];
}
