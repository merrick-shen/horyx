import 'package:flutter/material.dart';

import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/models/chess_piece.dart';
import 'package:horyx/games/chess/services/chess_rules.dart';
import 'package:horyx/games/chess/widgets/chess_board_view.dart';
import 'package:horyx/games/chess/widgets/chess_setup_view.dart';
import 'package:horyx/shared/pages/room_page.dart';
import 'package:horyx/shared/widgets/app_top_bar.dart';
import 'package:horyx/shared/widgets/confirm_dialog.dart';

/// 中国象棋游戏页
/// 持有对局状态（棋盘、行棋方、选中/预选走法、走子历史），统一负责：
/// 选子与走子交互、行棋方轮换、将军提示、将死/困毙终局弹窗、局域网建房入口
/// 存档恢复与悔棋在后续阶段接入
class ChessPage extends StatefulWidget {
  const ChessPage({super.key});

  /// 联机房间标识名：GameData 登记、建房入口与房间标识卡共用的
  /// 单一事实来源（注册数据归游戏模块自身，注册中心只做汇总）
  static const String gameName = '中国象棋';

  /// 游戏图标：与 [gameName] 同为注册数据的单一来源
  static const IconData gameIcon = Icons.grid_on_rounded;

  @override
  State<ChessPage> createState() => _ChessPageState();
}

class _ChessPageState extends State<ChessPage> {
  /// 是否已开始对局（false = 对局模式设置阶段）
  bool _started = false;

  /// 对局棋盘（开始对局时初始化为开局局面）
  ChessBoard? _board;

  /// 当前行棋方（红先黑后）
  ChessColor _turn = ChessColor.red;

  /// 当前选中的己方棋子；null 表示无选中
  ChessPos? _selected;

  /// 选中棋子的合法走法缓存（选中时由规则引擎计算）
  List<ChessMove> _legalMoves = const [];

  /// 待确认走法（ConfirmMoveRow 显示中）；null 表示无预选
  ChessMove? _pendingMove;

  /// 已确认走子序列（悔棋与存档的底层数据，阶段 8/9 接入 UI）
  final List<ChessMove> _history = [];

  /// 终局锁定（分出胜负后棋盘不可再走子）
  bool _gameOver = false;

  /// 「将军」闪烁提示触发计数：每检测到一次将军递增，
  /// 视图层据此重放一次渐现渐隐动画
  int _checkFlashTrigger = 0;

  /// 开始本地对局：进入对局视图，初始化开局局面（红先）
  void _onStart() {
    setState(() {
      _board = ChessBoard.initial();
      _turn = ChessColor.red;
      _history.clear();
      _clearSelection();
      _gameOver = false;
      _checkFlashTrigger = 0;
      _started = true;
    });
  }

  /// 清除选中与预选（选中态与预选态联动维护）
  void _clearSelection() {
    _selected = null;
    _legalMoves = const [];
    _pendingMove = null;
  }

  /// 点击棋盘格：选己方棋子 / 选中后点合法落点进入确认 / 点其他清除选中
  void _onCellTap(ChessPos pos) {
    if (_gameOver || _board == null) return;
    // 有待确认走法时先清除，再按普通选子流程处理
    if (_pendingMove != null) {
      setState(() => _pendingMove = null);
    }

    final piece = _board!.pieceAt(pos);
    if (piece != null && piece.color == _turn) {
      // 选/换己方棋子：重算合法走法缓存
      setState(() {
        _selected = pos;
        _legalMoves = ChessRules.legalMovesFor(_board!, pos);
      });
      return;
    }

    // 已有选中且点击合法落点：进入待确认（走点必须属于当前选中的走法集）
    if (_selected != null) {
      for (final move in _legalMoves) {
        if (move.to == pos) {
          setState(() => _pendingMove = move);
          return;
        }
      }
      // 非法落点/其他位置：清除选中
      setState(_clearSelection);
    }
  }

  /// 取消待确认走法（保留选中状态，可另选落点）
  void _cancelMove() {
    setState(() => _pendingMove = null);
  }

  /// 确认走子：执行走法、记录历史、行棋方轮换，随后做将军/终局判定
  void _confirmMove() {
    final move = _pendingMove;
    final board = _board;
    if (move == null || board == null) return;
    setState(() {
      board.applyMove(move);
      _history.add(move);
      _clearSelection();
      _turn = _turn == ChessColor.red ? ChessColor.black : ChessColor.red;
    });

    final endReason = ChessRules.judgeEnd(board, _turn);
    if (endReason != null) {
      // 终局：锁定棋盘并弹出胜负弹窗（将死/困毙）
      setState(() => _gameOver = true);
      _showEndDialog(endReason);
      return;
    }
    // 对方被将军：屏幕中央「将军」渐现渐隐提示
    if (ChessRules.isInCheck(board, _turn)) {
      setState(() => _checkFlashTrigger++);
    }
  }

  /// 终局胜负弹窗：再来一局 / 返回设置 / 留在终局棋盘查看
  /// [_turn] 此刻即无路可走的一方，胜方为对方
  Future<void> _showEndDialog(ChessEndReason reason) async {
    final winner = _turn == ChessColor.red ? '黑方' : '红方';
    final message = switch (reason) {
      ChessEndReason.checkmate => '将死对方，$winner赢得本局',
      ChessEndReason.stalemate => '对方无子可动（困毙），$winner获胜',
      ChessEndReason.resign => '$winner获胜', // 认输流程在阶段 9 接入
    };
    final result = await showConfirmDialog(
      context,
      title: '$winner胜利！',
      message: message,
      confirmLabel: '再来一局',
      neutralLabel: '返回设置',
    );
    if (!mounted) return;
    switch (result) {
      case ConfirmResult.confirm:
        _restartMatch();
      case ConfirmResult.neutral:
        _backToSetup();
      case ConfirmResult.cancel:
        // 留在终局棋盘查看棋型
        break;
    }
  }

  /// 再来一局：重开新对局（红先）
  void _restartMatch() {
    setState(() {
      _board = ChessBoard.initial();
      _turn = ChessColor.red;
      _history.clear();
      _clearSelection();
      _gameOver = false;
      _checkFlashTrigger = 0;
    });
  }

  /// 局域网模式：创建房间并进入等待页（固定 2 人，自己为玩家 1）
  /// 联机对局页尚未接入：满员后停留在等待页「即将开始」过渡态
  void _createRoom() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomPage.host(
          gameName: ChessPage.gameName,
          icon: ChessPage.gameIcon,
          capacity: 2,
        ),
      ),
    );
  }

  /// 回到设置视图并清空对局状态
  void _backToSetup() {
    setState(() {
      _board = null;
      _started = false;
      _turn = ChessColor.red;
      _clearSelection();
      _history.clear();
      _gameOver = false;
      _checkFlashTrigger = 0;
    });
  }

  /// 退出请求：设置阶段与终局锁定阶段直接退出页面，对局阶段回设置视图
  void _requestExit() {
    if (!_started || _gameOver) {
      Navigator.of(context).pop();
      return;
    }
    _backToSetup();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 对局阶段拦截系统返回（回设置视图），设置阶段与终局后允许直接返回
      canPop: !_started || _gameOver,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestExit();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppTopBar(
                title: '中国象棋',
                showBack: true,
                onBack: _requestExit,
              ),
              Expanded(
                // 阶段切换动画：设置视图 <-> 对局视图
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _started
                      ? _buildGameView()
                      : ChessSetupView(
                          key: const ValueKey('setup'),
                          onStart: _onStart,
                          onCreateRoom: _createRoom,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 对局视图：行棋提示 + 交互棋盘 + 确认行
  Widget _buildGameView() {
    final board = _board;
    if (board == null) {
      // _started 时必有棋盘；空值兜底回设置视图，防御异常路径
      _backToSetup();
      return const SizedBox.shrink();
    }
    return ChessBoardView(
      key: const ValueKey('board'),
      board: board,
      turn: _turn,
      selected: _selected,
      legalTargets: {for (final m in _legalMoves) m.to},
      pendingMove: _pendingMove,
      checkFlashTrigger: _checkFlashTrigger,
      onCellTap: _onCellTap,
      onCancelMove: _cancelMove,
      onConfirmMove: _confirmMove,
    );
  }
}
