import 'package:flutter/material.dart';

import 'package:horyx/shared/network/online_game_controller.dart';
import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/widgets/dialog_action_button.dart';

/// [EndGameReason] 的图标扩展：纯枚举下沉于 network 层（controllers
/// 与本组件共用），图标属 UI 表达，以扩展形式留在本文件
extension EndGameReasonIcon on EndGameReason {
  /// 弹窗头部图标（按原因语义区分）
  IconData get icon => switch (this) {
        EndGameReason.peerLeft => Icons.person_off_rounded,
        EndGameReason.hostDismissed => Icons.meeting_room_rounded,
        EndGameReason.disconnected => Icons.wifi_off_rounded,
        EndGameReason.dataError => Icons.error_outline_rounded,
      };
}

/// 联机终局弹窗：结束原因 + 单按钮返回
/// 适用于对局被迫终止且无胜负结果的场景（断线/房主解散/全员离开等）
/// 文案与图标按 [reason] 由组件内聚生成，调用方只传原因；
/// 有胜负结果的终局（如五子棋胜负）用通用确认弹窗展示更合适
class EndGameDialog extends StatelessWidget {
  const EndGameDialog({
    super.key,
    required this.reason,
    required this.onConfirm,
  });

  /// 终止原因（文案与图标由此内聚生成）
  final EndGameReason reason;

  /// 返回按钮回调
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      // 限制最大宽度：横屏时可用宽度是整个屏幕宽，内容 stretch 会把弹窗
      // 拉成一条长横幅，观感很差；宽度与确认弹窗一致（400）
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
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
              Icon(reason.icon, color: palette.textSecondary, size: 30),
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
                reason.text,
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
      ),
    );
  }
}
