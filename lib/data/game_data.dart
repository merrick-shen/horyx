import 'package:flutter/material.dart';

import '../models/game_info.dart';
import '../theme/app_theme.dart';

/// 静态游戏数据源（占位展示）
/// 当前所有卡片统一为「开发中」占位样式；接入真实游戏时替换为各自数据
abstract final class GameData {
  /// 占位卡片数量
  static const int placeholderCount = 8;

  static final List<GameInfo> games = List.generate(
    placeholderCount,
    (_) => const GameInfo(
      name: '开发中',
      description: '敬请期待',
      icon: Icons.construction_rounded,
      gradient: AppColors.brandGradient,
    ),
  );
}
