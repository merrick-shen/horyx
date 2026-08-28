import 'package:flutter/material.dart';

import 'package:horyx/shared/network/online_game_controller.dart';
import 'package:horyx/shared/utils/hint_bar.dart';
import 'package:horyx/shared/widgets/alert_dialog.dart';
import 'package:horyx/shared/widgets/app_top_bar.dart';
import 'package:horyx/shared/widgets/confirm_dialog.dart';
import 'package:horyx/shared/widgets/end_game_dialog.dart';

/// 联机对局页骨架（配合 [OnlineGameControllerBase] 使用）
/// 统一各联机对局页的同构结构：控制器生命周期（创建/挂提示/监听/销毁——
/// 销毁即关闭房间连接）、无胜负终止弹窗（断线/解散）、退出确认流程、
/// 顶栏 + 状态驱动对局视图的页面框架。
/// 游戏差异通过参数下沉：
/// - [createController]：游戏控制器工厂（host/client 模式由页面判定）
/// - [buildGameView]：对局视图构建（随控制器状态实时重建）
/// - [onGameEvent]：游戏特有事件钩子（如五子棋悔棋请求弹窗、胜负弹窗）
/// 终局语义：[OnlineGameControllerBase.gameEndedText] 非空即弹通用终局弹窗
/// 并标记终局（系统返回放行、退出免确认）；胜负类终局由游戏在
/// [onGameEvent] 中自行弹窗并调用 markEndShown 标记。
class OnlineGamePageShell<TController extends OnlineGameControllerBase>
    extends StatefulWidget {
  const OnlineGamePageShell({
    super.key,
    required this.title,
    required this.exitMessage,
    required this.createController,
    required this.buildGameView,
    this.onGameEvent,
  });

  /// 顶栏标题（如「五子棋 · 联机」）
  final String title;

  /// 退出确认弹窗的说明文案
  final String exitMessage;

  /// 游戏控制器工厂（initState 调用一次；销毁时由骨架统一 dispose）
  final TController Function() createController;

  /// 对局视图构建（ListenableBuilder 内随控制器状态重建）；
  /// [requestExit] 为骨架的退出请求（含终局免确认捷径），供对局内退出按钮复用
  final Widget Function(
    BuildContext context,
    TController controller,
    VoidCallback requestExit,
  ) buildGameView;

  /// 游戏特有事件钩子：控制器每次通知时先于通用终局判定调用。
  /// [markEndShown] 供游戏自行处理终局（胜负弹窗）后标记——
  /// 骨架跳过通用终局弹窗，终局后的返回放行/退出免确认随之生效。
  /// 返回 true 表示本次通知已消费（如弹出了悔棋请求弹窗），跳过终局判定。
  final bool Function(TController controller, VoidCallback markEndShown)?
      onGameEvent;

  @override
  State<OnlineGamePageShell<TController>> createState() =>
      _OnlineGamePageShellState<TController>();
}

class _OnlineGamePageShellState<TController extends OnlineGameControllerBase>
    extends State<OnlineGamePageShell<TController>> {
  late final TController _controller;

  /// 终局弹窗只弹一次（通用终止弹窗/游戏胜负弹窗共用标志）；
  /// 置位后系统返回放行、退出免确认
  bool _endDialogShown = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.createController();
    _controller.onHint = _showHint;
    _controller.addListener(_onControllerChanged);
    // 控制器构造期即已终局（如客户端开局载荷校验失败置 gameEndedText）
    // 时无人收到通知，帧回调后补一次终局判定；延后到 build 完成再弹窗，
    // 避免 initState 期间 showDialog 报 Navigator 未就绪
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onControllerChanged();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    // 控制器销毁会关闭底层房间连接（房主解散 / 客户端退出）
    _controller.dispose();
    super.dispose();
  }

  /// 控制器状态变化：先给游戏事件钩子（悔棋请求/胜负弹窗），
  /// 未消费则做通用终局判定（无胜负终止弹窗，只弹一次）
  void _onControllerChanged() {
    if (widget.onGameEvent?.call(_controller, _markEndShown) ?? false) return;
    if (_endDialogShown) return;
    final text = _controller.gameEndedText;
    if (text == null) return;
    _endDialogShown = true;
    _showEndDialog(text);
  }

  /// 游戏钩子标记终局已展示（见 [OnlineGamePageShell.onGameEvent]）
  void _markEndShown() {
    _endDialogShown = true;
  }

  /// 终局弹窗：不可点遮罩关闭（对局已终止，无内容可继续）
  Future<void> _showEndDialog(String message) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => EndGameDialog(
        message: message,
        onConfirm: () {
          Navigator.of(dialogContext).pop();
          _exitPage();
        },
      ),
    );
  }

  /// 退出请求：终局后（已弹过终局弹窗）直接返回，对局中确认后断开
  Future<void> _requestExit() async {
    if (_endDialogShown) {
      _exitPage();
      return;
    }
    final result = await showConfirmDialog(
      context,
      title: '退出对局？',
      message: widget.exitMessage,
      confirmLabel: '退出对局',
    );
    if (!mounted) return;
    if (result == ConfirmResult.confirm) {
      _exitPage();
    }
  }

  /// 退出页面：先移除未关闭的错误提示再返回
  void _exitPage() {
    if (!mounted) return;
    exitPageClean(context);
  }

  /// 展示校验拒绝等提示（沿用本地对局文案，底部长条形式，需手动关闭）
  /// 作为控制器回调挂接，通知可能晚于页面销毁到达，先检查 mounted
  void _showHint(String message) {
    if (!mounted) return;
    showAlertDialog(context, message: message);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 对局中拦截系统返回（走退出确认），终局后允许直接返回
      canPop: _endDialogShown,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          // 系统返回直接弹出（终局后 canPop）：绕过 _requestExit，需在此清理
          clearHint(context);
          return;
        }
        _requestExit();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppTopBar(
                title: widget.title,
                showBack: true,
                onBack: _requestExit,
              ),
              Expanded(
                // 对局视图随控制器状态实时重建（提交广播/终局判定）
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) =>
                      widget.buildGameView(context, _controller, _requestExit),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
