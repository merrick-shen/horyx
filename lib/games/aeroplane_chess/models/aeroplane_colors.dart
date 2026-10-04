import 'package:flutter/material.dart';

import 'package:horyx/games/aeroplane_chess/models/aeroplane_game_state.dart';

/// 飞行棋四色展示常量（棋盘渲染、棋子层与回合指示共用）
/// 四色是棋盘拓扑的固有属性，不随主题色变化（与象棋 ChessPieceColors、
/// 坦克 TankPlayer 同风格的游戏内语义色）；格上白点等棋盘固有配色
/// 一并集中于此，绘制层不写死色值
abstract final class AeroplaneColors {
  static const Color green = Color(0xFF7CB342);
  static const Color red = Color(0xFFD81B60);
  static const Color blue = Color(0xFF64B5F6);
  static const Color yellow = Color(0xFFEF6C00);

  /// 外环格 / 跑道格上的白色圆点与停机坪机位底色
  static const Color cellDot = Color(0xFFF7F4EA);

  /// 骰面点色：骰身与棋盘同为白底，点色为固有深色不随主题
  /// （白骰身上深浅主题均清晰）
  static const Color dicePip = Color(0xFF1B2136);

  /// 棋子专用色：与棋盘格/基地块同色系但明显加深，棋子停己色格
  /// 或己方基地上时靠深浅差分辨，不与底色融合
  static const Color pieceGreen = Color(0xFF33691E);
  static const Color pieceRed = Color(0xFFAD1457);
  static const Color pieceBlue = Color(0xFF1565C0);
  static const Color pieceYellow = Color(0xFFE65100);

  static Color of(AeroplaneColor color) => switch (color) {
        AeroplaneColor.green => green,
        AeroplaneColor.red => red,
        AeroplaneColor.blue => blue,
        AeroplaneColor.yellow => yellow,
      };

  static Color pieceOf(AeroplaneColor color) => switch (color) {
        AeroplaneColor.green => pieceGreen,
        AeroplaneColor.red => pieceRed,
        AeroplaneColor.blue => pieceBlue,
        AeroplaneColor.yellow => pieceYellow,
      };
}
