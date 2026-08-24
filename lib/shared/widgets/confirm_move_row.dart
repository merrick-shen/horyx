import 'package:flutter/material.dart';

import 'primary_button.dart';

/// 落子确认按钮行：棋盘有预选棋子时显示「取消/下棋」
///
/// 固定 48px 高度：按钮显隐切换时不挤压上方棋盘布局；
/// AnimatedSwitcher 提供淡入淡出过渡。三个棋盘视图（五子棋本地/联机、围棋）共用
class ConfirmMoveRow extends StatelessWidget {
  const ConfirmMoveRow({
    super.key,
    required this.visible,
    required this.onCancelMove,
    required this.onConfirmMove,
  });

  /// 是否显示（存在预选棋子时）
  final bool visible;

  /// 点击「取消」回调：清除落子预选
  final VoidCallback onCancelMove;

  /// 点击「下棋」回调：确认落子
  final VoidCallback onConfirmMove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: visible
            ? Row(
                key: const ValueKey('confirm_row'),
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: '取消',
                      outlined: true,
                      onPressed: onCancelMove,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      label: '下棋',
                      onPressed: onConfirmMove,
                    ),
                  ),
                ],
              )
            : const SizedBox.shrink(
                key: ValueKey('confirm_row_hidden'),
              ),
      ),
    );
  }
}
