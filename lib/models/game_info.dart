import 'package:flutter/material.dart';

/// 游戏展示数据模型
/// 当前阶段仅承载静态展示数据；后续接入真实游戏时复用此模型，UI 组件无需改动
class GameInfo {
  const GameInfo({
    required this.name,
    required this.description,
    required this.icon,
    required this.gradient,
  });

  /// 游戏名称
  final String name;

  /// 简短游戏描述
  final String description;

  /// 展示图标
  final IconData icon;

  /// 卡片专属渐变主题色，用于区分不同游戏的视觉标识
  final List<Color> gradient;
}
