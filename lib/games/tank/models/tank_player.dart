import 'package:flutter/material.dart';

/// 坦克动荡玩家（本地双人固定红绿两方）
enum TankPlayer {
  /// 红方（复刻原版：屏幕下方玩家）
  red,

  /// 绿方（复刻原版：屏幕上方玩家）
  green;

  /// 玩家主题色：坦克图标 / 摇杆中心钮 / 开火钮统一染色
  /// （白模素材用 multiply 染色：白色区域取玩家色，黑色描边保持不变）
  Color get color => switch (this) {
        TankPlayer.red => const Color(0xFFB92C23),
        TankPlayer.green => const Color(0xFF55B73C),
      };
}

/// 摇杆方向：坦克控制语义（上前进 / 下后退 / 左右原地转向）
enum TankMoveDirection { forward, backward, turnLeft, turnRight }

/// 白模素材染色滤镜：按通道缩放 RGB、保留 Alpha。
/// 白色区域取目标色、黑描边保持黑色、灰色暗部按比例加深。
/// 注意不能用 BlendMode.multiply：它会把图层透明区域刷成纯滤镜色
/// （Porter-Duff 的 src*(1-dstAlpha) 项），带透明底的素材会污染整屏
ColorFilter tintFilter(Color color) => ColorFilter.matrix([
      color.r, 0, 0, 0, 0, //
      0, color.g, 0, 0, 0, //
      0, 0, color.b, 0, 0, //
      0, 0, 0, 1, 0,
    ]);
