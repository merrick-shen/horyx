import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'dialog_action_button.dart';

/// 联机终局弹窗：结束原因 + 单按钮返回
/// 适用于对局被迫终止且无胜负结果的场景（断线/房主解散/全员离开等）
/// 有胜负结果的终局（如五子棋胜负）用通用确认弹窗展示更合适
class EndGameDialog extends StatelessWidget {
  const EndGameDialog({
    super.key,
    required this.message,
    required this.onConfirm,
    this.icon = Icons.link_off_rounded,
  });

  /// 结束原因（面向用户的完整文案）
  final String message;

  /// 返回按钮回调
  final VoidCallback onConfirm;

  /// 头部图标（默认断连图标，可按结束原因替换）
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: palette.surfaceBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(icon, color: palette.textSecondary, size: 30),
            const SizedBox(height: 12),
            Text(
              '对局已结束',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            DialogActionButton(
              label: '返回',
              filled: true,
              onPressed: onConfirm,
            ),
          ],
        ),
      ),
    );
  }
}
