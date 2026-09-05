import 'dart:ui' as ui;

import 'package:flutter/services.dart';

final Map<String, Future<ui.Image>> _cache = {};

/// 读取打包资产并解码为 [ui.Image]。
/// 按路径缓存解码 Future：同一路径全应用只解码一次，并发调用共享
/// 同一次解码（如坦克战场与比分烟雾共用 explosion_smoke.png，
/// 原先各自 rootBundle 加载解码两次）；解码失败同样缓存，
/// 重复请求直接得到同一错误，不会反复读取损坏资产
Future<ui.Image> loadAssetImage(String asset) {
  return _cache.putIfAbsent(asset, () async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  });
}
