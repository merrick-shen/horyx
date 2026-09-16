import 'package:flutter/material.dart';

import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/update/models/release_info.dart';
import 'package:horyx/shared/widgets/dialog_action_button.dart';

/// 发现新版本弹窗（更新检测）
/// 视觉规范复用通用确认弹窗（surfaceBg / 圆角 24 / 描边），配色随主题；
/// Release 说明完整显示不截断，超长时滚动并提供可见的滚动指示
///
/// 返回 true 表示用户选择「前往下载」，下载跳转由调用方执行
Future<bool> showUpdateAvailableDialog(
  BuildContext context, {
  required ReleaseInfo release,
}) async {
  final download = await showDialog<bool>(
    context: context,
    builder: (_) => _UpdateAvailableDialog(release: release),
  );
  return download ?? false;
}

/// 正文区限高（超出即进入滚动形态，弹窗不撑出屏幕）
const _bodyMaxHeight = 300.0;

/// 正文与右侧滚动条的留白间隙（避免拇指压住文字）
const _scrollbarGap = 8.0;

class _UpdateAvailableDialog extends StatefulWidget {
  const _UpdateAvailableDialog({required this.release});

  final ReleaseInfo release;

  @override
  State<_UpdateAvailableDialog> createState() => _UpdateAvailableDialogState();
}

class _UpdateAvailableDialogState extends State<_UpdateAvailableDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 判断说明文本在给定宽度下是否超出限高（决定是否启用滚动形态）
  /// 测量宽度与实际渲染宽度（扣除滚动条间隙）保持一致，边界判定不失真
  bool _bodyOverflows(double maxWidth, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: widget.release.body, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth - _scrollbarGap);
    final overflows = painter.height > _bodyMaxHeight;
    painter.dispose();
    return overflows;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      // 限制最大宽度：横屏时可用宽度是整个屏幕宽，内容 stretch 会把弹窗
      // 拉成一条长横幅，观感很差（同通用确认弹窗）
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
              Text(
                '发现新版本 ${widget.release.tagName}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              // Release 说明可能为空（发布时未填），为空时省略正文区
              if (widget.release.body.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildBody(palette),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: DialogActionButton(
                      label: '下次再说',
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DialogActionButton(
                      label: '前往下载',
                      filled: true,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 说明正文：未超限高时直接平铺；超限时进入滚动形态，
  /// 常驻滚动条 + 底部渐隐双重指示，让用户明确知道可滚动
  Widget _buildBody(AppPalette palette) {
    final style = TextStyle(
      color: palette.textSecondary,
      fontSize: 13.5,
      height: 1.5,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_bodyOverflows(constraints.maxWidth, style)) {
          return Text(widget.release.body, style: style);
        }
        return SizedBox(
          height: _bodyMaxHeight,
          child: Stack(
            children: [
              // 常驻滚动条：弹窗内无 PrimaryScrollController，必须显式传 controller
              Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                thickness: 4,
                radius: const Radius.circular(4),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(right: _scrollbarGap),
                  child: Text(widget.release.body, style: style),
                ),
              ),
              // 底部渐隐：与背景同色过渡，暗示下方还有内容
              Positioned(
                left: 0,
                right: _scrollbarGap,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          palette.surfaceBg.withValues(alpha: 0),
                          palette.surfaceBg,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
