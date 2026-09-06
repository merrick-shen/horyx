import 'package:flutter/material.dart';

import 'package:horyx/shared/game/game_data.dart';
import 'package:horyx/games/gomoku/models/gomoku_game_state.dart';
import 'package:horyx/games/gomoku/services/gomoku_rules.dart';
import 'package:horyx/games/gomoku/services/gomoku_storage.dart';
import 'package:horyx/shared/storage/archive_storage.dart';
import 'package:horyx/shared/storage/game_archive_state.dart';
import 'package:horyx/shared/widgets/app_top_bar.dart';
import 'package:horyx/shared/widgets/confirm_dialog.dart';
import 'package:horyx/games/gomoku/widgets/board_view.dart';
import 'package:horyx/games/gomoku/widgets/setup_view.dart';
import 'package:horyx/shared/pages/room_page.dart';
import 'package:horyx/games/gomoku/pages/gomoku_online_page.dart';

/// 五子棋游戏页
/// 持有对局状态（落子序列、预选、胜负），统一负责：
/// 落子确认、五连判定、胜利弹窗、退出确认与对局存档恢复
/// 状态栏样式由 MaterialApp 的 builder 统一处理（随主题亮度变化）
class GomokuPage extends StatefulWidget {
  const GomokuPage({super.key});

  @override
  State<GomokuPage> createState() => _GomokuPageState();
}

class _GomokuPageState
    extends GameArchiveStateBase<GomokuPage, GomokuGameState> {
  /// 是否已开始对局（false = 规格设置阶段）
  bool _started = false;

  /// 棋盘路数（15 标准盘 / 19 大盘）
  int _boardSize = 15;

  /// 已确认落子序列（索引奇偶决定黑白：0=黑 1=白）
  final List<(int, int)> _moves = [];

  /// 已占位集合（与 _moves 同步增删，点击占位判定 O(1)，
  /// 悔棋/恢复/清盘处必须同步维护，否则判定失真）
  final Set<(int, int)> _occupied = {};

  /// 预选落子位置；null 表示无预选
  (int, int)? _pending;

  /// 胜方（'黑方'/'白方'）；null 表示对局进行中
  String? _winner;

  @override
  ArchiveStorage<GomokuGameState> get archiveStorage =>
      GomokuStorage.instance;

  @override
  bool get isInSetupPhase => !_started;

  @override
  void initState() {
    super.initState();
    loadSavedState();
  }

  /// 点击棋盘交叉点：终局或已有棋子的点不可选，其余更新预选
  void _onCellTap(int col, int row) {
    if (_winner != null) return;
    if (_occupied.contains((col, row))) return;
    setState(() => _pending = (col, row));
  }

  /// 取消预选：预选棋子消失
  void _cancelMove() {
    setState(() => _pending = null);
  }

  /// 确认落子：预选棋子转正式，执子方轮换；胜利时弹出结果弹窗
  void _confirmMove() {
    final selected = _pending;
    if (selected == null) return;
    final (col, row) = selected;
    setState(() {
      _moves.add(selected);
      _occupied.add(selected);
      _pending = null;
    });

    // 刚落子的一方：落子后序列长度奇偶判断（黑先）
    final blackMoved = _moves.length.isOdd;
    if (GomokuRules.hasFiveInRow(_moves, _boardSize, col, row, blackMoved)) {
      setState(() => _winner = blackMoved ? '黑方' : '白方');
      // 对局已分胜负，立即清除存档：避免重进页面恢复出已结束的局面
      GomokuStorage.instance.clear();
      _showWinDialog();
    }
  }

  /// 胜利弹窗：再来一局 / 返回设置 / 查看棋盘
  Future<void> _showWinDialog() async {
    final winner = _winner;
    if (winner == null) return;

    final result = await showConfirmDialog(
      context,
      title: '$winner胜利！',
      message: '五子连珠，$winner赢得本局',
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

  /// 再来一局：清盘并回到黑方执子（保持当前棋盘规格）
  void _restartMatch() {
    setState(() {
      _moves.clear();
      _occupied.clear();
      _pending = null;
      _winner = null;
    });
  }

  /// 返回设置视图：清盘后重新选择规格；
  /// 同时重新加载存档刷新恢复入口——开局时入口已被置空（savedState = null），
  /// 未落子即退出时磁盘上的旧存档仍在，回设置后应重新展示
  void _backToSetup() {
    setState(() {
      _moves.clear();
      _occupied.clear();
      _pending = null;
      _winner = null;
      _started = false;
    });
    loadSavedState();
  }

  /// 悔棋：撤回最后一颗确认棋子，执子方回退
  void _undo() {
    if (_moves.isEmpty) return;
    setState(() {
      // removeLast 返回被移除的元素，同步清出占位集合
      _occupied.remove(_moves.removeLast());
      _pending = null;
    });
  }

  void _onStart() {
    setState(() {
      _started = true;
      // 开启新对局后不再展示旧存档入口
      savedState = null;
    });
  }

  /// 局域网模式：创建房间并进入等待页（固定 2 人，自己执黑先行）
  /// 满员后等待页自动跳转联机对局页（连接所有权随之移交）；
  /// 所选规格随开局载荷广播，客户端据此构建同规格棋盘
  void _createRoom(int boardSize) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomPage.host(
          gameName: GameData.gomoku.name,
          capacity: 2,
          gameStartPayload: {'boardSize': boardSize},
          hostGameBuilder: (context, host) =>
              GomokuOnlinePage.host(host: host, boardSize: boardSize),
        ),
      ),
    );
  }

  /// 恢复未完成对局：从存档还原棋盘规格与落子序列
  void _resumeSaved() {
    final saved = savedState;
    if (saved == null) return;
    setState(() {
      _boardSize = saved.boardSize;
      _moves
        ..clear()
        ..addAll(saved.moves);
      _occupied
        ..clear()
        ..addAll(saved.moves);
      _started = true;
      savedState = null;
    });
  }

  /// 退出请求：对局中弹出三选项确认弹窗（保存退出/不保存退出/取消）
  /// 对局中尚无落子时无进行中内容，直接返回设置视图（与计分器未计分退出一致）
  /// 设置阶段与终局查看棋型阶段无进行中对局，直接退出页面
  Future<void> _requestExit() async {
    if (!_started || _winner != null) {
      Navigator.of(context).pop();
      return;
    }
    // 开局后还没落任何一手：不打扰，直接回设置
    if (_moves.isEmpty) {
      _backToSetup();
      return;
    }
    await confirmExitWithArchive(
      this,
      // 持久化完整对局状态后退出
      onSave: () => GomokuStorage.instance.save(
        GomokuGameState(
          boardSize: _boardSize,
          moves: List.of(_moves),
          savedAt: DateTime.now(),
        ),
      ),
      onDiscard: GomokuStorage.instance.clear,
      onExit: () => Navigator.of(context).pop(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 对局中拦截系统返回（走保存确认弹窗），设置阶段允许直接返回
      canPop: !_started || _winner != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestExit();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppTopBar(
                title: '五子棋',
                showBack: true,
                onBack: _requestExit,
              ),
              Expanded(
                // 阶段切换动画：设置视图 <-> 对局视图淡入淡出
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _started
                      ? GomokuBoardView(
                          key: const ValueKey('board'),
                          boardSize: _boardSize,
                          moves: _moves,
                          pending: _pending,
                          winner: _winner,
                          onCellTap: _onCellTap,
                          onCancelMove: _cancelMove,
                          onConfirmMove: _confirmMove,
                          onUndo: _undo,
                          onRestart: _restartMatch,
                        )
                      : GomokuSetupView(
                          key: const ValueKey('setup'),
                          boardSize: _boardSize,
                          onSelect: (size) =>
                              setState(() => _boardSize = size),
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
}
