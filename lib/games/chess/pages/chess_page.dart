import 'package:flutter/material.dart';

import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/models/chess_game_state.dart';
import 'package:horyx/games/chess/models/chess_piece.dart';
import 'package:horyx/games/chess/pages/chess_online_page.dart';
import 'package:horyx/games/chess/services/chess_rules.dart';
import 'package:horyx/games/chess/services/chess_storage.dart';
import 'package:horyx/games/chess/widgets/chess_board_view.dart';
import 'package:horyx/games/chess/widgets/chess_setup_view.dart';
import 'package:horyx/shared/pages/room_page.dart';
import 'package:horyx/shared/profile/profile_controller.dart';
import 'package:horyx/shared/storage/archive_storage.dart';
import 'package:horyx/shared/storage/game_archive_state.dart';
import 'package:horyx/shared/widgets/app_top_bar.dart';
import 'package:horyx/shared/widgets/confirm_dialog.dart';

/// 中国象棋游戏页
/// 持有对局状态（棋盘、行棋方、选中/预选走法、走子历史），统一负责：
/// 选子与走子交互、行棋方轮换、将军提示、将死/困毙终局弹窗、
/// 退出存档与恢复续玩、局域网建房入口
/// 悔棋在后续阶段接入
class ChessPage extends StatefulWidget {
  const ChessPage({super.key, this.resumeArchiveId});

  /// 存档管理页「开始」按钮定点恢复的存档 id；null 表示常规进入
  final String? resumeArchiveId;

  /// 联机房间标识名：GameRegistry 登记、建房入口与房间标识卡共用的
  /// 单一事实来源（注册数据归游戏模块自身，注册中心只做汇总）
  static const String gameName = '中国象棋';

  /// 游戏图标：与 [gameName] 同为注册数据的单一来源
  static const IconData gameIcon = Icons.grid_on_rounded;

  @override
  State<ChessPage> createState() => _ChessPageState();
}

class _ChessPageState
    extends GameArchiveStateBase<ChessPage, ChessGameState> {
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

  /// 已确认走子序列（存档与悔棋的数据底座）；同时记录每步被吃子，
  /// 悔棋 revertMove 时需恢复被吃子（存档序列化时仅取走子部分）
  final List<(ChessMove, ChessPiece?)> _history = [];

  /// 终局锁定（分出胜负后棋盘不可再走子）
  bool _gameOver = false;

  /// 「将军」闪烁提示触发计数：每检测到一次将军递增，
  /// 视图层据此重放一次渐现渐隐动画
  int _checkFlashTrigger = 0;

  /// 最近一步走法（棋盘走子滑动动画用）：确认走子时记录，
  /// 悔棋/重开/回设置/恢复存档时清空（回退类局面变化不播滑行动画）
  ChessMove? _lastMove;

  /// 最近一步被吃的棋子（动画期间暂留显示在终点位，随 [_lastMove] 一并清空）
  ChessPiece? _capturedPiece;

  /// 走子动画触发序号（单调递增，不复位）：与 [_lastMove] 配合供棋盘
  /// 判定"新走法"——相同起终点的走法先后发生时走法记录相等，
  /// 仅靠走法判等会漏触发
  int _moveSeq = 0;

  /// 恢复存档时的局面基线（棋盘编码 + 轮次）：退出时与当前局面比对，
  /// 一致（含悔棋净零变化）则视为未产生新进度，直接退出且存档保持原样；
  /// 非恢复进入（新开局/重开）为 null
  String? _restoredBoardCode;
  ChessColor? _restoredTurn;

  @override
  ArchiveStorage<ChessGameState> get archiveStorage =>
      ChessStorage.instance;

  @override
  bool get isInSetupPhase => !_started;

  @override
  void initState() {
    super.initState();
    // 进入页面即检测未完成存档，存在则在设置视图展示恢复入口
    loadSavedState();
    final resumeId = widget.resumeArchiveId;
    if (resumeId != null) {
      resumeArchiveById(resumeId, _applySavedState);
    }
  }

  /// 恢复未完成对局：从存档还原局面、轮次与走子历史
  void _resumeSaved() {
    final saved = takeResumeEntry();
    if (saved == null) return;
    _applySavedState(saved);
  }

  /// 将存档状态还原进对局视图（恢复入口与存档管理页「开始」共用）
  void _applySavedState(ChessGameState saved) {
    try {
      // 从初始局面正向重放走子序列还原棋盘，并顺带收集每步被吃子
      // （悔棋 revertMove 需要；存档只存走子不存被吃子，无法直接还原），
      // 重放终局面与 boardCode 不一致视为存档内部矛盾（损坏）
      final board = ChessBoard.initial();
      final history = <(ChessMove, ChessPiece?)>[];
      for (final move in saved.moves) {
        history.add((move, board.applyMove(move)));
      }
      if (board.encode() != saved.boardCode) {
        throw const FormatException('存档走子序列与局面不一致');
      }
      setState(() {
        _board = board;
        _turn = saved.turn;
        _history
          ..clear()
          ..addAll(history);
        _clearSelection();
        _lastMove = null;
        _capturedPiece = null;
        _gameOver = false;
        _checkFlashTrigger = 0;
        _started = true;
        _restoredBoardCode = saved.boardCode;
        _restoredTurn = saved.turn;
      });
    } catch (_) {
      // 存档损坏（局面编码非法/历史矛盾）：删除该档（恢复目标已绑定），
      // 与 ArchiveStorage 读侧「损坏数据视为无存档」的容错风格一致
      clearCurrentArchive();
    }
  }

  /// 开始本地对局：进入对局视图，初始化开局局面（红先）
  void _onStart() {
    setState(() {
      _board = ChessBoard.initial();
      _turn = ChessColor.red;
      _history.clear();
      _clearSelection();
      _lastMove = null;
      _capturedPiece = null;
      _gameOver = false;
      _checkFlashTrigger = 0;
      _started = true;
      _restoredBoardCode = null;
      _restoredTurn = null;
      // 开启新对局：关闭恢复入口并解绑覆盖目标，此后保存新建存档
      discardResumeEntry();
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

  /// 悔棋：确认后撤销最近一步（棋子搬回起点并恢复被吃子），行棋方回退，
  /// 同时清除选中与待确认状态；无子可悔时不响应
  Future<void> _undo() async {
    final board = _board;
    if (board == null || _history.isEmpty) return;
    final result = await showConfirmDialog(
      context,
      title: '悔棋',
      message: '确定撤回上一步棋吗？',
      confirmLabel: '悔棋',
    );
    if (!mounted || result != ConfirmResult.confirm) return;
    setState(() {
      final (move, captured) = _history.removeLast();
      board.revertMove(move, captured);
      _clearSelection();
      _lastMove = null;
      _capturedPiece = null;
      _turn = _turn == ChessColor.red ? ChessColor.black : ChessColor.red;
    });
  }

  /// 确认走子：执行走法、记录历史、行棋方轮换，随后做将军/终局判定
  void _confirmMove() {
    final move = _pendingMove;
    final board = _board;
    if (move == null || board == null) return;
    setState(() {
      final captured = board.applyMove(move);
      _history.add((move, captured));
      _lastMove = move;
      _capturedPiece = captured;
      _moveSeq++;
      _clearSelection();
      _turn = _turn == ChessColor.red ? ChessColor.black : ChessColor.red;
    });

    final endReason = ChessRules.judgeEnd(board, _turn);
    if (endReason != null) {
      // 终局：对局已分胜负，立即清除存档（避免重进恢复出已结束的局面），
      // 随后锁定棋盘并弹出胜负弹窗（将死/困毙）
      clearCurrentArchive();
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
      ChessEndReason.resign => '$winner获胜', // 认输首版不实现，本地无该入口
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
      _lastMove = null;
      _capturedPiece = null;
      _gameOver = false;
      _checkFlashTrigger = 0;
      _restoredBoardCode = null;
      _restoredTurn = null;
    });
  }

  /// 局域网模式：创建房间并进入等待页（固定 2 人，自己为玩家 1）
  /// 满员后等待页自动跳转联机对局页（连接所有权随之移交）；
  /// 象棋无规格选项，gameStartPayload 保持空对象
  Future<void> _createRoom() async {
    if (!await ensureProfileForOnline(context)) return;
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomPage.host(
          gameName: ChessPage.gameName,
          hostName: ProfileScope.of(context).name,
          icon: ChessPage.gameIcon,
          capacity: 2,
          hostGameBuilder: (context, host) => ChessOnlinePage.host(host: host),
        ),
      ),
    );
  }

  /// 回到设置视图并清空对局状态（终局弹窗「返回设置」路径）；
  /// 存档检测刷新由 [_resetForSetup] 后的统一 loadSavedState 负责
  void _backToSetup() {
    _resetForSetup();
    loadSavedState();
  }

  /// 清空对局状态回到设置视图（不含存档检测——退出模板的回设置分支
  /// 与 [_backToSetup] 各自统一负责刷新，避免双份加载）
  void _resetForSetup() {
    setState(() {
      _board = null;
      _started = false;
      _turn = ChessColor.red;
      _clearSelection();
      _history.clear();
      _lastMove = null;
      _capturedPiece = null;
      _gameOver = false;
      _checkFlashTrigger = 0;
      _restoredBoardCode = null;
      _restoredTurn = null;
    });
  }

  /// 退出请求：设置阶段与终局查看阶段直接退出页面；
  /// 对局中未走子时无进行中内容，直接回设置视图（不打扰）；
  /// 已有走子弹出三选项确认弹窗（保存并退出/直接退出/取消）
  Future<void> _requestExit() async {
    await requestExitWithArchive(
      this,
      hasProgress: _started && !_gameOver,
      hasMoves: _history.isNotEmpty,
      unchangedSinceRestore: _board != null &&
          _board!.encode() == _restoredBoardCode &&
          _turn == _restoredTurn,
      // 局部引用防异步期间状态变化：_started 且未终局时必有棋盘，
      // null 为不可达的纯防御路径——无从保存，放弃保存留在本页
      // （恢复链路覆盖原档，新对局新建存档）
      onSave: () {
        final board = _board;
        if (board == null) return Future<void>.value();
        return saveCurrent(
          ChessGameState(
            boardCode: board.encode(),
            turn: _turn,
            moves: [for (final (move, _) in _history) move],
            savedAt: DateTime.now(),
          ),
        );
      },
      onBackToSetup: _resetForSetup,
      exitPage: () => Navigator.of(context).pop(),
    );
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
          // 顶部由 AppTopBar 自行吸收状态栏（表面色整体延伸），此处不再避让
          top: false,
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
                          savedState: savedState,
                          onResume: _resumeSaved,
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
      // 不变式：_started 为 true 时必有棋盘，此分支不可达（纯防御）。
      // 不可在 build 期间调 _backToSetup()（内含 setState 会抛框架错误），
      // 改为 debug 断言暴露回归、release 渲染占位帧；顶栏返回仍可退出
      assert(false, '_started 为 true 时 _board 不应为 null');
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
      gameOver: _gameOver,
      canUndo: _history.isNotEmpty,
      lastMove: _lastMove,
      capturedPiece: _capturedPiece,
      lastMoveSeq: _moveSeq,
      onCellTap: _onCellTap,
      onCancelMove: _cancelMove,
      onConfirmMove: _confirmMove,
      onUndo: _undo,
      onRestart: _restartMatch,
    );
  }
}
