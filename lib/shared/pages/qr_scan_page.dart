import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:horyx/shared/widgets/primary_button.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 扫码加入房间页：识别房主等待页展示的房间二维码
/// 识别成功后携带二维码原文 pop 返回，解析与进房由调用方负责
/// 相机权限由 mobile_scanner 启动时自动申请，被拒时展示系统设置引导文案
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final _controller = MobileScannerController(
    // 仅识别 QR 格式：房间码为二维码，过滤其他条码类型减少误识别
    formats: [BarcodeFormat.qrCode],
  );

  /// 是否已成功识别并返回（onDetect 连续回调，防止重复 pop）
  bool _completed = false;

  @override
  void dispose() {
    // dispose 为异步，State.dispose 中无法等待，fire-and-forget 即可
    unawaited(_controller.dispose());
    super.dispose();
  }

  /// 识别回调：首个含有效内容的二维码触发返回
  void _onDetect(BarcodeCapture capture) {
    if (_completed || !mounted) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      _completed = true;
      // 成功反馈：轻微震动；先停相机再退出，避免返回后相机仍短暂占用
      HapticFeedback.mediumImpact();
      unawaited(_controller.stop());
      Navigator.of(context).pop(raw);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // SizedBox.expand 撑满整页：否则 Stack 按唯一非定位子项（顶栏，高度
      // 约为状态栏 + 64）收缩，Positioned.fill 的相机层只剩一条窄条
      body: SizedBox.expand(
        child: Stack(
          children: [
            // 相机层：LayoutBuilder 计算 scanWindow，
            // 识别窗口与遮罩镂空经 _scanWindowFor 同源对齐
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) => MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  scanWindow: _scanWindowFor(constraints.biggest),
                  // 遮罩与提示仅相机运行时叠加（overlayBuilder 特性）：
                  // 错误视图不被蒙层遮挡，也不会被蒙层拦截点击
                  overlayBuilder: _buildScanOverlay,
                  errorBuilder: _buildErrorView,
                ),
              ),
            ),
            // 顶栏浮于最上层，任何状态下都可返回
            SafeArea(
              bottom: false,
              child: _buildTopBar(),
            ),
          ],
        ),
      ),
    );
  }

  /// 取景框：短边 70%（上限 280），屏幕居中
  /// scanWindow（识别窗口）与遮罩镂空共用本函数，保证视觉与识别范围一致
  Rect _scanWindowFor(Size size) {
    final windowSide = math.min(size.shortestSide * 0.7, 280.0);
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: windowSide,
      height: windowSide,
    );
  }

  /// 相机运行时的叠加层：暗色遮罩镂空取景框 + 下方操作提示
  /// overlayBuilder 与 scanWindow 使用同一份 constraints，镂空必然对齐
  Widget _buildScanOverlay(BuildContext context, BoxConstraints constraints) {
    final scanWindow = _scanWindowFor(constraints.biggest);
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: _ScanMaskPainter(window: scanWindow)),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: scanWindow.bottom + 24,
          child: Text(
            '对准房主等待页的房间二维码即可自动加入',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  /// 顶栏：返回按钮 + 居中标题 + 手电筒开关（样式对齐 AppTopBar）
  Widget _buildTopBar() {
    return SizedBox(
      height: 64,
      child: Stack(
        children: [
          const Center(
            child: Text(
              '扫码加入房间',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          // 手电筒：仅相机运行中可用；不可用时隐藏
          Align(
            alignment: Alignment.centerRight,
            child: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, _) {
                final torchOn = state.torchState == TorchState.on;
                if (!state.isInitialized ||
                    !state.isRunning ||
                    state.torchState == TorchState.unavailable) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  icon: Icon(
                    torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    // 开启时用亮黄提示当前状态
                    color: torchOn ? Colors.amberAccent : Colors.white,
                    size: 22,
                  ),
                  onPressed: () => unawaited(_controller.toggleTorch()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 相机错误视图：权限被拒给系统设置引导，其余错误提示重试
  /// （全屏黑底替换相机画面，顶栏仍在最上层可返回）
  Widget _buildErrorView(BuildContext context, MobileScannerException error) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                denied
                    ? Icons.no_photography_rounded
                    : Icons.error_outline_rounded,
                color: Colors.white.withValues(alpha: 0.85),
                size: 40,
              ),
              const SizedBox(height: 16),
              Text(
                denied ? '未获得相机权限' : '相机启动失败',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                denied
                    ? '扫码加入需要使用相机，请在系统设置中允许本应用使用相机后重试'
                    : '请返回后重新进入扫码页重试',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: '返回',
                outlined: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 扫码遮罩画笔：全屏半透明黑，取景框区域镂空并描边
class _ScanMaskPainter extends CustomPainter {
  _ScanMaskPainter({required this.window});

  /// 取景框区域（与 MobileScanner.scanWindow 同源，识别窗口与视觉框一致）
  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final hole = Path()
      ..addRRect(RRect.fromRectAndRadius(window, const Radius.circular(20)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, overlay, hole),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(window, const Radius.circular(20)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_ScanMaskPainter oldDelegate) =>
      oldDelegate.window != window;

  /// 蒙层不参与命中测试：否则整层拦截点击，压在其下的按钮全部失效
  /// （RenderCustomPaint 在 painter 未覆写 hitTest 时默认整屏可命中）
  @override
  bool? hitTest(Offset position) => false;
}
