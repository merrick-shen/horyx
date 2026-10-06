import 'package:flutter/material.dart';

import 'package:horyx/games/gomoku/services/gomoku_audio.dart';
import 'package:horyx/games/gomoku/services/gomoku_online_controller.dart';
import 'package:horyx/games/gomoku/widgets/gomoku_game_layout.dart';
import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/network/room_host.dart';
import 'package:horyx/shared/network/undo_resign_negotiation.dart';
import 'package:horyx/shared/widgets/board_game_online_page.dart';
import 'package:horyx/shared/widgets/online_game_page_shell.dart';

/// 五子棋联机对局页
/// 由房间等待页满员开局后接管房间连接（房主/客户端所有权移入本页）。
/// 页面骨架（控制器生命周期/终局弹窗/退出确认/顶栏框架）见
/// [OnlineGamePageShell]，悔棋/认输协商与终局弹窗的三段式事件处理、
/// 底部操作按钮见共享层 [BoardGameOnlinePageMixin]/[BoardGameActionBar]，
/// 本页只实现五子棋的交互与视图：预选落子与胜负文案组装。
/// 视图结构与本地对局一致（执子卡 + 棋盘 + 操作按钮），联机适配点：
/// 仅轮到自己时可预选/确认落子，落子经房主校验后随广播全端生效。
/// 页面销毁即退出对局并关闭连接（联机对局不落本地存档）。
/// 再来一局暂未支持，终局后仅提供退出对局。
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

class _GomokuOnlinePageState extends State<GomokuOnlinePage>
    with BoardGameOnlinePageMixin<GomokuOnlinePage> {
  /// 预选落子位置；null 表示无预选（与本地对局一致的落子交互）
  (int, int)? _pending;

  @override
  void initState() {
    super.initState();
    // 后台预载音效（不 await、不阻塞首帧；未就绪期间的播放静默跳过）
    GomokuAudio.preload();
  }

  /// 对方请求悔棋的弹窗说明文案（撤销"上一手棋"）
  @override
  String get undoRequestMessage => '对方希望撤销上一手棋，是否同意？';

  /// 游戏事件钩子：委托共享层三段式处理（悔棋弹窗/终局关弹窗/胜负弹窗），
  /// 胜负弹窗的文案按五子棋终局语义组装
  bool _onGameEvent(
    GomokuOnlineController controller,
    VoidCallback markEndShown,
  ) {
    return handleGameEvent(
      controller,
      markEndShown: markEndShown,
      showWinDialog: () => _showWinDialog(controller),
    );
  }

  /// 胜利弹窗：区分五连获胜/认输；可留在棋盘查看棋型
  /// 中途退出不产生胜负（走骨架终局弹窗，无胜方），不进此弹窗
  Future<void> _showWinDialog(GomokuOnlineController controller) async {
    final winner = controller.winnerText!;
    final String message;
    if (controller.wonByResign) {
      message = controller.winnerSeat == controller.mySeat
          ? '对方认输了，你获得胜利'
          : '你认输了，本局告负';
    } else {
      message = '五子连珠，$winner赢得本局';
    }
    await showBoardGameWinDialog(
      context,
      winner: winner,
      message: message,
      onExit: exitBoardGamePage,
    );
  }

  /// 点击棋盘交叉点：仅轮到自己时可预选，终局或已占的点不可选
  void _onCellTap(GomokuOnlineController controller, int col, int row) {
    if (controller.winnerSeat != null) return;
    if (!controller.isMyTurn) return;
    if (controller.moves.contains((col, row))) return;
    setState(() => _pending = (col, row));
  }

  /// 取消预选：预选棋子消失
  void _cancelMove() {
    setState(() => _pending = null);
  }

  /// 确认落子：提交房主校验（房主模式即时生效，客户端随广播生效）
  /// 拒绝时经 onHint 提示原因，通过时清除预选等待同步
  void _confirmMove(GomokuOnlineController controller) {
    final selected = _pending;
    if (selected == null) return;
    if (controller.submitStone(selected.$1, selected.$2)) {
      setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnlineGamePageShell<GomokuOnlineController>(
      title: '五子棋 · 联机',
      exitMessage: '退出后将断开与房间的连接，对局将结束',
      createController: () => widget.host != null
          ? GomokuOnlineController.host(
              widget.host!,
              boardSize: widget.boardSize,
            )
          : GomokuOnlineController.client(widget.client!),
      onGameEvent: _onGameEvent,
      buildGameView: (context, controller, requestExit) => _BoardView(
        boardSize: controller.boardSize,
        moves: controller.moves,
        pending: _pending,
        isMyTurn: controller.isMyTurn,
        winnerSeat: controller.winnerSeat,
        ended: controller.gameEndedText != null,
        undoState: controller.undoState,
        hasMoves: controller.moves.isNotEmpty,
        onCellTap: (col, row) => _onCellTap(controller, col, row),
        onCancelMove: _cancelMove,
        onConfirmMove: () => _confirmMove(controller),
        onRequestUndo: () => requestUndoFor(controller),
        onResign: () => requestResignFor(controller),
        onExit: requestExit,
      ),
    );
  }
}

/// 联机对局视图：与本地对局同构（执子卡 + 棋盘 + 操作按钮）
/// 差异点：执子卡副标题提示等待对象；悔棋为协商制（发起请求、
/// 对方应答后随广播回退）；终局后按钮为「退出对局」（再来一局暂未支持），
/// 底部操作按钮组为棋类共用组件 [BoardGameActionBar]
class _BoardView extends StatelessWidget {
  const _BoardView({
    required this.boardSize,
    required this.moves,
    required this.pending,
    required this.isMyTurn,
    required this.winnerSeat,
    required this.ended,
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

  /// 对局是否无胜负终止（断线/解散/对方离开）
  final bool ended;

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
    // 落子确认按钮仅在棋盘上有预选棋子时出现（终局后无预选），由布局组件处理
    final winner = winnerSeat == null ? null : (winnerSeat == 1 ? '黑方' : '白方');

    // 布局骨架（执子卡 + 棋盘 + 确认行）与本地对局共用 [GomokuGameLayout]，
    // 仅执子卡副标题（联机提示等待对象）与底部按钮集（协商制操作组）不同
    return GomokuGameLayout(
      boardSize: boardSize,
      moves: moves,
      pending: pending,
      winner: winner,
      turnSubtitle: isMyTurn ? '轮到你落子' : '等待对方落子',
      onCellTap: onCellTap,
      onCancelMove: onCancelMove,
      onConfirmMove: onConfirmMove,
      actions: BoardGameActionBar(
        showExit: winner != null || ended,
        undoState: undoState,
        hasMoves: hasMoves,
        isMyTurn: isMyTurn,
        onRequestUndo: onRequestUndo,
        onResign: onResign,
        onExit: onExit,
      ),
    );
  }
}
