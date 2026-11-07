import 'package:flutter/material.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_colors.dart';

/// 飞行棋覆盖层提示状态（本地与联机对局页共用）：[showHint] 递增触发
/// 序号驱动 [HintOverlay] 重播动画，文本为空不显示；回合重置时将
/// [hintTrigger] 归零、[hintText] 清空（无需 setState 的场景直接赋值）
mixin AeroplaneHintState<T extends StatefulWidget> on State<T> {
  /// 提示触发序号（递增播放）
  int hintTrigger = 0;

  /// 提示文本（空串不显示）
  String hintText = '';

  /// 提示语义色
  Color hintColor = AeroplaneColors.red;

  /// 触发覆盖层提示
  void showHint(String text, Color color) {
    setState(() {
      hintTrigger++;
      hintText = text;
      hintColor = color;
    });
  }
}
