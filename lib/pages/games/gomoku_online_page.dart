import 'package:flutter/material.dart';

import '../../services/gomoku/gomoku_online_controller.dart';
import '../../services/network/room_client.dart';
import '../../services/network/room_host.dart';
import '../../theme/app_theme.dart';
import '../../utils/hint_bar.dart';
import '../../widgets/common/app_top_bar.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/end_game_dialog.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/common/stone_board.dart';
import '../../widgets/common/turn_card.dart';

/// 五子棋联机对局页
/// 由房间等待页满员开局后接管房间连接（房主/客户端所有权移入本页），
/// 视图结构与本地对局一致（执子卡 + 棋盘 + 操作按钮），联机适配点：
/// 仅轮到自己时可预选/确认落子，落子经房主校验后随广播全端生效。
/// 页面销毁即退出对局并关闭连接（联机对局不落本地存档）。
/// 悔棋/再来一局协商为后续步骤，当前悔棋按钮呈禁用态占位。
class GomokuOnlinePage extends StatefulWidget {
  const GomokuOnlinePage.host({
    super.key,
    required this.host,
    required this.boardSize,
  }) : client = null;

  const GomokuOnlinePage.client({super.key, required this.client})
      : host = null,
        boardSize = 0;

  /// 房主连接（房主模式；与本页生命周期绑定，dispose 时关闭即解散房间）
  final RoomHost? host;

  /// 客户端连接（客户端模式；dispose 时关闭即退出房间）
  final RoomClient? client;

  /// 建房所选棋盘规格（仅房主模式有效；客户端从开局载荷读取）
  final int boardSize;

  @override
  State<GomokuOnlinePage> createState() => _GomokuOnlinePageState();
}

class _GomokuOnlinePageState extends State<GomokuOnlinePage> {
  late final GomokuOnlineController _controller;

  /// 预选落子位置；null 表示无预选（与本地对局一致的落子交互）
  (int, int)? _pending;

  /// 终局弹窗只弹一次（胜负/断线/解散共用一个标志）
  bool _endDialogShown = false;

  /// 悔棋应答弹窗防重入（应答后复位，允许下次请求再弹）
  bool _undoDialogShown = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.host != null
        ? GomokuOnlineController.host(widget.host!,
            boardSize: widget.boardSize)
        : GomokuOnlineController.client(widget.client!);
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

  /// 控制器状态变化：终局时弹窗告知（只处理一次）；
  /// 对方发起悔棋请求时弹应答弹窗
  void _onControllerChanged() {
    // 悔棋请求弹窗（未终局且非自己已发起状态）
    if (_controller.undoState == UndoState.peerRequesting &&
        !_undoDialogShown) {
      _undoDialogShown = true;
      _showUndoRequestDialog();
      return;
    }
    if (_endDialogShown) return;
    final ended = _controller.gameEndedText ?? _controller.winnerText;
    if (ended == null) return;
    _endDialogShown = true;
    // 无胜负的终止（断线/解散）走终局弹窗；胜负走胜利弹窗
    if (_controller.gameEndedText != null) {
      _showEndedDialog(_controller.gameEndedText!);
    } else {
      _showWinDialog();
    }
  }

  /// 对方悔棋请求的应答弹窗：同意/拒绝后复位弹窗标志
  /// 同意则棋盘随广播回退，拒绝则对方收到提示
  Future<void> _showUndoRequestDialog() async {
    final result = await showConfirmDialog(
      context,
      title: '对方请求悔棋',
      message: '对方希望撤销上一手棋，是否同意？',
      confirmLabel: '同意',
      cancelLabel: '拒绝',
    );
    if (!mounted) return;
    setState(() => _undoDialogShown = false);
    _controller.respondUndo(result == ConfirmResult.confirm);
  }

  /// 点击棋盘交叉点：仅轮到自己时可预选，终局或已占的点不可选
  void _onCellTap(int col, int row) {
    if (_controller.winnerSeat != null) return;
    if (!_controller.isMyTurn) return;
    if (_controller.moves.contains((col, row))) return;
    setState(() => _pending = (col, row));
  }

  /// 取消预选：预选棋子消失
  void _cancelMove() {
    setState(() => _pending = null);
  }

  /// 确认落子：提交房主校验（房主模式即时生效，客户端随广播生效）
  /// 拒绝时经 onHint 提示原因，通过时清除预选等待同步
  void _confirmMove() {
    final selected = _pending;
    if (selected == null) return;
    if (_controller.submitStone(selected.$1, selected.$2)) {
      setState(() => _pending = null);
    }
  }

  /// 胜利弹窗：区分五连获胜/认输；可留在棋盘查看棋型
  /// 中途退出不产生胜负（走终局弹窗，无胜方），不进此弹窗
  Future<void> _showWinDialog() async {
    final winner = _controller.winnerSeat == 1 ? '黑方' : '白方';
    final String message;
    if (_controller.wonByResign) {
      message = _controller.winnerSeat == _controller.mySeat
          ? '对方认输了，你获得胜利'
          : '你认输了，本局告负';
    } else {
      message = '五子连珠，$winner赢得本局';
    }
    final result = await showConfirmDialog(
      context,
      title: '$winner胜利！',
      message: message,
      confirmLabel: '退出对局',
      cancelLabel: '查看棋盘',
    );
    if (!mounted) return;
    if (result == ConfirmResult.confirm) {
      _exitPage();
    }
  }

  /// 断线/解散终局弹窗：不可点遮罩关闭（对局已终止，无内容可继续）
  Future<void> _showEndedDialog(String message) async {
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

  /// 发起悔棋请求（按钮回调）：交控制器进入协商状态
  void _requestUndo() {
    if (_controller.undoState != UndoState.idle) return;
    _controller.requestUndo();
    setState(() {}); // 刷新按钮为「等待对方应答…」禁用态
  }

  /// 认输请求（按钮回调）：确认后判对方获胜
  Future<void> _requestResign() async {
    final result = await showConfirmDialog(
      context,
      title: '认输？',
      message: '认输后本局将判定对方获胜',
      confirmLabel: '认输',
    );
    if (!mounted) return;
    if (result == ConfirmResult.confirm) {
      _controller.resign();
    }
  }

  /// 退出请求：对局进行中确认后断开（对局随之结束、不判胜负，与单词PK一致），
  /// 终局后（已弹过终局弹窗）直接返回
  Future<void> _requestExit() async {
    if (_endDialogShown) {
      _exitPage();
      return;
    }
    final result = await showConfirmDialog(
      context,
      title: '退出对局？',
      message: '退出后将断开与房间的连接，对局将结束',
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

  /// 展示校验拒绝等提示（沿用本地对局：不自动消失，需手动关闭）
  /// 作为控制器回调挂接，通知可能晚于页面销毁到达，先检查 mounted
  void _showHint(String message) {
    if (!mounted) return;
    showPersistentHint(context, message);
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
                title: '五子棋 · 联机',
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
                // 棋盘视图随控制器状态实时重建（落子广播/终局判定）
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => _BoardView(
                    boardSize: _controller.boardSize,
                    moves: _controller.moves,
                    pending: _pending,
                    isMyTurn: _controller.isMyTurn,
                    winnerSeat: _controller.winnerSeat,
                    undoState: _controller.undoState,
                    hasMoves: _controller.moves.isNotEmpty,
                    onCellTap: _onCellTap,
                    onCancelMove: _cancelMove,
                    onConfirmMove: _confirmMove,
                    onRequestUndo: _requestUndo,
                    onResign: _requestResign,
                    onExit: _requestExit,
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

/// 联机对局视图：与本地对局同构（执子卡 + 棋盘 + 操作按钮）
/// 差异点：执子卡副标题提示等待对象；悔棋禁用（协商悔棋后续接入）；
/// 终局后按钮为「退出对局」（再来一局协商后续接入）
class _BoardView extends StatelessWidget {
  const _BoardView({
    required this.boardSize,
    required this.moves,
    required this.pending,
    required this.isMyTurn,
    required this.winnerSeat,
    required this.undoState,
    required this.hasMoves,
    required this.onCellTap,
    required this.onCancelMove,
    required this.onConfirmMove,
    required this.onRequestUndo,
    required this.onResign,
    required this.onExit,
  });

  /// 棋盘路数（房主建房所选，随开局广播同步）
  final int boardSize;

  /// 已生效落子序列
  final List<(int, int)> moves;

  /// 预选落子位置；null 表示无预选
  final (int, int)? pending;

  /// 是否轮到自己落子（false 时棋盘不响应预选）
  final bool isMyTurn;

  /// 胜方座位号；null 表示对局进行中
  final int? winnerSeat;

  /// 悔棋协商状态（awaitingPeer 时悔棋按钮禁用防重复发起）
  final UndoState undoState;

  /// 是否已有落子（无子可悔时悔棋按钮禁用）
  final bool hasMoves;

  /// 点击棋盘交叉点回调
  final void Function(int col, int row) onCellTap;

  /// 点击「取消」回调：清除落子预选
  final VoidCallback onCancelMove;

  /// 点击「下棋」回调：确认落子
  final VoidCallback onConfirmMove;

  /// 点击「悔棋」回调：向对方发起悔棋请求
  final VoidCallback onRequestUndo;

  /// 点击「认输」回调：确认后判对方获胜
  final VoidCallback onResign;

  /// 终局后点击「退出对局」回调
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    // 落子确认按钮仅在棋盘上有预选棋子时出现
    final hasPending = pending != null;
    // 终局后无预选
    final isOver = winnerSeat != null;
    final blackTurn = moves.length.isEven;
    final winner = winnerSeat == null
        ? null
        : (winnerSeat == 1 ? '黑方' : '白方');

    return SizedBox.expand(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 对局中提示执子方与等待对象；终局提示胜方（图标色对应棋子）
                TurnCard(
                  icon: Icons.circle_rounded,
                  iconColor: (isOver ? !blackTurn : blackTurn)
                      ? StoneBoard.blackStone
                      : StoneBoard.whiteStone,
                  subtitle: isOver
                      ? '对局结束'
                      : (isMyTurn ? '轮到你落子' : '等待对方落子'),
                  title: isOver ? '$winner胜利' : (blackTurn ? '黑方' : '白方'),
                  titleKey: ValueKey(
                    isOver ? '$winner胜利' : (blackTurn ? '黑方' : '白方'),
                  ),
                ),
                const SizedBox(height: 16),
                // 棋盘占据剩余空间，正方形自适应宽高较小者
                Expanded(
                  child: Center(
                    child: StoneBoard(
                      size: boardSize,
                      stones: [
                        for (int i = 0; i < moves.length; i++)
                          (moves[i].$1, moves[i].$2, i.isEven),
                      ],
                      pending: pending == null
                          ? null
                          : (
                              pending!.$1,
                              pending!.$2,
                              moves.length.isEven,
                            ),
                      onCellTap: onCellTap,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 固定高度占位：确认按钮显隐时不挤压棋盘布局（与本地一致）
                SizedBox(
                  height: 48,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: hasPending
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
                ),
                const SizedBox(height: 12),
                if (isOver)
                  // 终局：退出对局（再来一局需双方协商，后续步骤接入）
                  PrimaryButton(
                    label: '退出对局',
                    icon: Icons.logout_rounded,
                    onPressed: onExit,
                  )
                else ...[
                  // 悔棋：等对方应答期间/无子可悔时禁用，防重复发起
                  PrimaryButton(
                    label: undoState == UndoState.awaitingPeer
                        ? '等待对方应答…'
                        : '悔棋',
                    icon: Icons.undo_rounded,
                    onPressed: undoState == UndoState.idle && hasMoves
                        ? onRequestUndo
                        : null,
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: '认输',
                    icon: Icons.flag_rounded,
                    onPressed: onResign,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
