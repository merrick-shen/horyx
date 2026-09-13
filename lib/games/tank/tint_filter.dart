import 'dart:ui';

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
