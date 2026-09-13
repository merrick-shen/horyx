import 'package:flutter/material.dart';

import 'package:horyx/games/tank/tint_filter.dart';

/// 原版同款开火按钮：玩家色圆环 + 黑色中心圆点（白模染色）
/// 按压缩放反馈；开火逻辑由对局页接入
class TankFireButton extends StatefulWidget {
  const TankFireButton({
    super.key,
    required this.color,
    required this.onTap,
    this.size = 68,
  });

  /// 按钮染色（玩家色）
  final Color color;

  /// 点击回调
  final VoidCallback onTap;

  /// 按钮直径
  final double size;

  @override
  State<TankFireButton> createState() => _TankFireButtonState();
}

class _TankFireButtonState extends State<TankFireButton> {
  /// 按压中缩小反馈
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1,
        duration: const Duration(milliseconds: 100),
        child: ColorFiltered(
          colorFilter: tintFilter(widget.color),
          child: Image.asset(
            'assets/tank/fire_button.png',
            width: widget.size,
            height: widget.size,
          ),
        ),
      ),
    );
  }
}
