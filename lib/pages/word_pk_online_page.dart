import 'package:flutter/material.dart';

import '../services/network/room_client.dart';
import '../services/network/room_host.dart';
import '../services/word_pk_online_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/word_pk/board_view.dart';

/// 单词PK 联机对局页
/// 由房间等待页满员开局后接管房间连接（房主/客户端所有权移入本页），
/// 复用本地对局视图展示；提交统一经房主校验，全端随广播同步。
/// 页面销毁即退出对局并关闭连接（联机对局不落本地存档）。
class WordPkOnlinePage extends StatefulWidget {
  const WordPkOnlinePage.host({super.key, required this.host})
      : client = null;

  const WordPkOnlinePage.client({super.key, required this.client})
      : host = null;

  /// 房主连接（房主模式；与本页生命周期绑定，dispose 时关闭即解散房间）
  final RoomHost? host;

  /// 客户端连接（客户端模式；dispose 时关闭即退出房间）
  final RoomClient? client;

  @override
  State<WordPkOnlinePage> createState() => _WordPkOnlinePageState();
}

class _WordPkOnlinePageState extends State<WordPkOnlinePage> {
  late final WordPkOnlineController _controller;

  /// 终局弹窗只弹一次（断线/解散/全员离开）
  bool _endDialogShown = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.host != null
        ? WordPkOnlineController.host(widget.host!)
        : WordPkOnlineController.client(widget.client!);
    _controller.onHint = _showHint;
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    // 控制器销毁会关闭底层房间连接（房主解散 / 客户端退出）
    _controller.dispose();
    super.dispose();
  }

  /// 对局中断（断线/房主解散/全员离开）：弹窗告知并返回
  void _onControllerChanged() {
    final text = _controller.gameEndedText;
    if (text != null && !_endDialogShown) {
      _endDialogShown = true;
      _showEndDialog(text);
    }
  }

  /// 终局弹窗：不可点遮罩关闭（对局已终止，无内容可继续）
  Future<void> _showEndDialog(String message) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _EndGameDialog(
        message: message,
        onConfirm: () {
          Navigator.of(dialogContext).pop();
          _exitPage();
        },
      ),
    );
  }

  /// 退出请求：确认后断开连接并返回（其他人会收到离开/解散提示）
  Future<void> _requestExit() async {
    final result = await showConfirmDialog(
      context,
      title: '退出对局？',
      message: '退出后将断开与房间的连接，已提交的单词不会保存',
      confirmLabel: '退出对局',
    );
    if (!mounted) return;
    if (result == ConfirmResult.confirm) {
      _exitPage();
    }
  }

  /// 退出页面：先移除未关闭的错误提示再返回
  /// SnackBar 挂在应用级 ScaffoldMessenger 上，不随页面销毁，需主动清理
  void _exitPage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    Navigator.of(context).pop();
  }

  /// 展示校验拒绝等提示（沿用本地对局：不自动消失，需手动关闭）
  void _showHint(String message) {
    if (!mounted) return;
    // 捕获 messenger state 而非在回调里依赖页面 context：
    // 提示可能比页面存活更久，引用已销毁 context 会导致「知道了」失效
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(days: 1),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '知道了',
            onPressed: () => messenger.hideCurrentSnackBar(),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 对局中拦截系统返回（走退出确认），终局弹窗阶段允许返回
      canPop: _endDialogShown,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestExit();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppTopBar(
                title: '单词PK · 联机',
                leading: IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: context.palette.textPrimary,
                    size: 20,
                  ),
                  onPressed: _requestExit,
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => WordPkBoardView(
                    playerCount: _controller.playerCount,
                    currentPlayer: _controller.currentPlayer,
                    entries: _controller.entries,
                    onSubmit: _controller.submitWord,
                    // 终局后禁输（连接已断，提交无处可去）
                    inputEnabled:
                        _controller.isMyTurn && _controller.gameEndedText == null,
                    selfSeat: _controller.mySeat,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 终局弹窗：对局结束原因 + 单按钮返回（风格与确认弹窗一致）
class _EndGameDialog extends StatelessWidget {
  const _EndGameDialog({required this.message, required this.onConfirm});

  /// 结束原因（断线/房主解散/全员离开）
  final String message;

  /// 返回按钮回调
  final VoidCallback onConfirm;

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
            Icon(
              Icons.link_off_rounded,
              color: palette.textSecondary,
              size: 30,
            ),
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
            GestureDetector(
              onTap: onConfirm,
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.primary,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(
                      color: palette.primary.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Text(
                  '返回',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
