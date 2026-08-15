import 'package:flutter/material.dart';

import '../models/game_info.dart';

/// 静态游戏数据源
/// 已上线的游戏使用各自真实数据，未开发的游戏以「开发中」占位
abstract final class GameData {
  /// 占位卡片数量（开发中的游戏）
  static const int placeholderCount = 6;

  /// 单词PK：首位已上线游戏
  static const GameInfo wordPk = GameInfo(
    name: '单词PK',
    description: '轮流拼写英文单词，考验词汇量的回合对决',
    icon: Icons.spellcheck_rounded,
  );

  /// 五子棋：玩法开发中，卡片先行展示
  static const GameInfo gomoku = GameInfo(
    name: '五子棋',
    description: '黑白轮流落子，先连成五子者胜',
    icon: Icons.grid_on_rounded,
  );

  static final List<GameInfo> games = [
    wordPk,
    gomoku,
    // 其余游戏保持占位展示
    ...List.generate(
      placeholderCount,
      (_) => const GameInfo(
        name: '开发中',
        description: '敬请期待',
        icon: Icons.construction_rounded,
      ),
    ),
  ];
}
