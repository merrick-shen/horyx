import 'package:flutter/material.dart';

import '../../models/games/weiqi_game_state.dart';
import '../../services/weiqi/weiqi_rules.dart';
import '../../services/storage/weiqi_storage.dart';
import '../../utils/hint_bar.dart';
import '../../widgets/common/app_top_bar.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/stone_board.dart';
import '../../widgets/weiqi/board_view.dart';
import '../../widgets/weiqi/setup_view.dart';

/// 围棋游戏页
/// 持有对局状态（着手序列、预选、执子方），统一负责：
/// 落子校验（自杀/打劫）、提子、虚手轮换、悔棋回退、终局数子、
/// 退出确认与对局存档恢复
/// 棋盘/提子数/执子方/局面历史均由着手序列重放派生（单一数据源，
/// 悔棋与重开免费回退，规则判定经 WeiqiRules 引擎执行）
/// 状态栏样式由 MaterialApp 的 builder 统一处理（随主题亮度变化）
class WeiqiPage extends StatefulWidget {
  const WeiqiPage({super.key});

  @override
  State<WeiqiPage> createState() => _WeiqiPageState();
}

/// 单步着手：落子（pass 为 false）或虚手（pass 为 true，坐标无意义置 -1）
/// 虚手也必须记入序列：悔棋按着手回退执子方，含虚手的对局才能正确撤销
typedef _Move = ({int col, int row, bool black, bool pass});

class _WeiqiPageState extends State<WeiqiPage> {
  /// 是否已开始对局（false = 规格设置阶段）
  bool _started = false;

  /// 棋盘路数（9 小盘 / 13 中盘 / 19 标准盘）
  int _boardSize = 9;

  /// 已完成的着手序列（落子与虚手按发生顺序记录，唯一数据源）
  final List<_Move> _moves = [];

  /// 预选落子位置；null 表示无预选
  (int, int)? _pending;

  // ---- 以下均为着手序列的派生状态（_recompute 统一重算） ----

  /// 当前局面（一维棋盘：0 空 / 1 黑 / 2 白）
  List<int> _board = const [];

  /// 历史局面集合（禁全同判定用，含当前局面）
  Set<String> _positionHistory = {};

  /// 当前棋子集合（通用棋盘组件绘制用）
  List<Stone> _stones = const [];

  /// 当前执黑方（黑先；落子与虚手后均轮换）
  bool _blackToMove = true;

  /// 黑方提子数（黑吃掉的白子数）
  int _blackCaptures = 0;

  /// 白方提子数（白吃掉的黑子数）
  int _whiteCaptures = 0;

  /// 是否终局（连续双虚手触发）；终局后棋盘锁定
  bool _gameOver = false;

  /// 胜方（'黑方'/'白方'）；终局时由数子结果得出
  String? _winner;

  /// 终局数子结果（弹窗展示用）
  int _scoreBlack = 0;
  int _scoreWhite = 0;

  /// 进入时检测到的未完成存档；恢复或开始新对局后清空展示
  WeiqiGameState? _savedState;

  @override
  void initState() {
    super.initState();
    _loadSavedState();
  }

  /// 启动时检测未完成对局，存在则在设置视图展示恢复入口
  Future<void> _loadSavedState() async {
    final state = await WeiqiStorage.load();
    if (state != null && mounted) {
      setState(() => _savedState = state);
    }
  }

  /// 点击棋盘交叉点：先经引擎校验合法性，非法时提示且不进入预选
  void _onCellTap(int col, int row) {
    if (_gameOver) return;
    final (result, _, _) = WeiqiRules.tryPlace(
      _board,
      _boardSize,
      col,
      row,
      _blackToMove,
      _positionHistory,
    );
    switch (result) {
      case WeiqiPlaceResult.occupied:
        break; // 已有棋子静默忽略（与五子棋一致）
      case WeiqiPlaceResult.suicide:
        showPersistentHint(context, '此处不能落子（自杀手）');
      case WeiqiPlaceResult.repetition:
        showPersistentHint(context, '打劫：不能立即回提');
      case WeiqiPlaceResult.ok:
        setState(() => _pending = (col, row));
    }
  }

  /// 取消预选：预选棋子消失
  void _cancelMove() {
    setState(() => _pending = null);
  }

  /// 确认落子：预选点已在校验时确认合法，直接入列并重算派生状态
  void _confirmMove() {
    final selected = _pending;
    if (selected == null) return;
    final (col, row) = selected;
    _moves.add((col: col, row: row, black: _blackToMove, pass: false));
    _pending = null;
    _recompute();
    // 合法落子生效后清除遗留的非法提示，避免误导
    hideHint(context);
  }

  /// 虚手（停一手）：不落子仅轮换执子方，记入着手序列供悔棋回退
  void _pass() {
    _moves.add((col: -1, row: -1, black: _blackToMove, pass: true));
    _pending = null;
    _recompute();
    // 连续两手虚手 → 终局数子
    final n = _moves.length;
    if (n >= 2 && _moves[n - 1].pass && _moves[n - 2].pass) {
      _finishGame();
    }
  }

  /// 悔棋：撤回最后一步着手（落子或虚手），执子方与棋盘同步回退
  void _undo() {
    if (_moves.isEmpty) return;
    _moves.removeLast();
    _pending = null;
    setState(() {
      _gameOver = false;
      _winner = null;
    });
    _recompute();
  }

  /// 终局：数子判定胜负，弹出结果弹窗（在 setState 之后调用，避免构建期间弹窗）
  void _finishGame() {
    final (black, white) = WeiqiRules.score(_board, _boardSize);
    setState(() {
      _scoreBlack = black;
      _scoreWhite = white;
      // 黑贴 7.5：盘面点差超过贴目则黑胜；0.5 尾数保证不会平局
      _winner = black - white - WeiqiRules.komi > 0 ? '黑方' : '白方';
      _gameOver = true;
    });
    // 对局已结束，未完成存档随之失效（避免下次误入已终局的棋局）
    WeiqiStorage.clear();
    _showResultDialog();
  }

  /// 终局结果弹窗：再来一局 / 返回设置 / 留在棋盘复盘
  Future<void> _showResultDialog() async {
    final winner = _winner;
    if (winner == null) return;
    final margin = (_scoreBlack - _scoreWhite - WeiqiRules.komi).abs();
    final result = await showConfirmDialog(
      context,
      title: '$winner胜利！',
      message:
          '数子结果 黑 $_scoreBlack 子 · 白 $_scoreWhite 子，'
          '贴 ${WeiqiRules.komi} 后$winner以 $margin 子优势获胜',
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
        break; // 留在终局棋盘复盘
    }
  }

  /// 再来一局：清盘重开，保持当前规格（黑先）
  void _restartMatch() {
    _moves.clear();
    _pending = null;
    setState(() {
      _gameOver = false;
      _winner = null;
    });
    _recompute();
  }

  /// 返回设置页：清盘并回到规格选择
  void _backToSetup() {
    // 终局前可能遗留非法落子提示，回设置视图前清理
    clearHint(context);
    _moves.clear();
    _pending = null;
    setState(() {
      _gameOver = false;
      _winner = null;
      _started = false;
    });
    _recompute();
  }

  void _onStart() {
    setState(() {
      _started = true;
      // 开启新对局后不再展示旧存档入口
      _savedState = null;
    });
    _recompute(); // 初始化空盘派生状态（局面历史含初始空盘）
  }

  /// 恢复未完成对局：从存档还原棋盘规格与着手序列，重放派生状态
  void _resumeSaved() {
    final saved = _savedState;
    if (saved == null) return;
    _boardSize = saved.boardSize;
    _moves
      ..clear()
      ..addAll(saved.moves);
    _pending = null;
    setState(() {
      _started = true;
      _savedState = null;
    });
    _recompute();
  }

  /// 重放着手序列，重算全部派生状态（棋盘/棋子/提子数/执子方/局面历史）
  /// 重放中每手必合法：落子入口已校验，非法着手不会进入序列
  void _recompute() {
    final total = _boardSize * _boardSize;
    var board = List<int>.filled(total, 0);
    var blackToMove = true;
    var blackCaptures = 0;
    var whiteCaptures = 0;
    final history = <String>{WeiqiRules.serialize(board)};
    final stones = <Stone>[];

    for (final m in _moves) {
      if (m.pass) {
        blackToMove = !blackToMove;
        continue;
      }
      final (_, next, captured) = WeiqiRules.tryPlace(
        board,
        _boardSize,
        m.col,
        m.row,
        m.black,
        history,
      );
      board = next;
      history.add(WeiqiRules.serialize(board));
      if (m.black) {
        blackCaptures += captured;
      } else {
        whiteCaptures += captured;
      }
      blackToMove = !blackToMove;
    }

    // 一维棋盘转棋子集合（供通用棋盘组件绘制）
    for (var i = 0; i < total; i++) {
      if (board[i] == 0) continue;
      stones.add((i % _boardSize, i ~/ _boardSize, board[i] == 1));
    }

    setState(() {
      _board = board;
      _positionHistory = history;
      _stones = stones;
      _blackToMove = blackToMove;
      _blackCaptures = blackCaptures;
      _whiteCaptures = whiteCaptures;
    });
  }

  /// 退出请求：对局中弹出三选项确认弹窗（保存退出/不保存退出/取消）
  /// 对局中尚无着手时无进行中内容，直接返回设置视图（与计分器未计分退出一致）
  /// 设置阶段与终局复盘阶段无进行中对局，直接退出页面
  Future<void> _requestExit() async {
    // 提示挂在应用级 ScaffoldMessenger，不随页面销毁，进入退出流程先清理
    clearHint(context);
    if (!_started || _gameOver) {
      Navigator.of(context).pop();
      return;
    }
    // 开局后还没下任何一手（含虚手）：不打扰，直接回设置
    if (_moves.isEmpty) {
      _backToSetup();
      return;
    }
    final result = await showConfirmDialog(
      context,
      title: '退出对局？',
      message: '保存并退出后，下次进入可从当前进度继续对弈',
      confirmLabel: '保存并退出',
      neutralLabel: '不保存并退出',
    );
    if (!mounted) return;

    switch (result) {
      case ConfirmResult.confirm:
        // 持久化完整着手序列后退出（重放架构下恢复即完整还原盘面）
        await WeiqiStorage.save(
          WeiqiGameState(
            boardSize: _boardSize,
            moves: List.of(_moves),
            savedAt: DateTime.now(),
          ),
        );
        if (mounted) Navigator.of(context).pop();
      case ConfirmResult.neutral:
        // 放弃当前对局：清除旧存档，避免下次误提示可继续
        await WeiqiStorage.clear();
        if (mounted) Navigator.of(context).pop();
      case ConfirmResult.cancel:
        // 留在对局
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 对局中拦截系统返回（走保存确认弹窗），设置/终局阶段允许直接返回
      canPop: !_started || _gameOver,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          // 系统返回直接弹出（设置/终局阶段 canPop）：绕过 _requestExit，需在此清理
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
                title: '围棋',
                showBack: true,
                onBack: _requestExit,
              ),
              Expanded(
                // 阶段切换动画：设置视图 <-> 对局视图淡入淡出
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _started
                      ? WeiqiBoardView(
                          key: const ValueKey('board'),
                          boardSize: _boardSize,
                          stones: _stones,
                          pending: _pending,
                          blackToMove: _blackToMove,
                          gameOver: _gameOver,
                          winner: _winner,
                          blackCaptures: _blackCaptures,
                          whiteCaptures: _whiteCaptures,
                          canUndo: _moves.isNotEmpty,
                          onCellTap: _onCellTap,
                          onCancelMove: _cancelMove,
                          onConfirmMove: _confirmMove,
                          onUndo: _undo,
                          onPass: _pass,
                          onRestart: _restartMatch,
                        )
                      : WeiqiSetupView(
                          key: const ValueKey('setup'),
                          boardSize: _boardSize,
                          onSelect: (size) => setState(() => _boardSize = size),
                          onStart: _onStart,
                          savedState: _savedState,
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
}
