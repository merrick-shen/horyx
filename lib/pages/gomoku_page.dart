import 'package:flutter/material.dart';

import '../models/gomoku_game_state.dart';
import '../services/gomoku_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/option_block.dart';
import '../widgets/panel_card.dart';
import '../widgets/primary_button.dart';
import '../widgets/resume_card.dart';
import '../widgets/stone_board.dart';
import '../widgets/turn_card.dart';

/// 五子棋游戏页
/// 持有对局状态（落子序列、预选、胜负），统一负责：
/// 落子确认、五连判定、胜利弹窗、退出确认与对局存档恢复
/// 状态栏样式由 MaterialApp 的 builder 统一处理（随主题亮度变化）
class GomokuPage extends StatefulWidget {
  const GomokuPage({super.key});

  @override
  State<GomokuPage> createState() => _GomokuPageState();
}

class _GomokuPageState extends State<GomokuPage> {
  /// 是否已开始对局（false = 规格设置阶段）
  bool _started = false;

  /// 棋盘路数（15 标准盘 / 19 大盘）
  int _boardSize = 15;

  /// 已确认落子序列（索引奇偶决定黑白：0=黑 1=白）
  final List<(int, int)> _moves = [];

  /// 预选落子位置；null 表示无预选
  (int, int)? _pending;

  /// 胜方（'黑方'/'白方'）；null 表示对局进行中
  String? _winner;

  /// 进入时检测到的未完成存档；恢复或开始新对局后清空展示
  GomokuGameState? _savedState;

  @override
  void initState() {
    super.initState();
    _loadSavedState();
  }

  /// 启动时检测未完成对局，存在则在设置视图展示恢复入口
  Future<void> _loadSavedState() async {
    final state = await GomokuStorage.load();
    if (state != null && mounted) {
      setState(() => _savedState = state);
    }
  }

  /// 点击棋盘交叉点：终局或已有棋子的点不可选，其余更新预选
  void _onCellTap(int col, int row) {
    if (_winner != null) return;
    if (_moves.contains((col, row))) return;
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
      _pending = null;
    });

    // 刚落子的一方：落子后序列长度奇偶判断（黑先）
    final blackMoved = _moves.length.isOdd;
    if (_hasFiveInRow(col, row, blackMoved)) {
      setState(() => _winner = blackMoved ? '黑方' : '白方');
      _showWinDialog();
    }
  }

  /// 五连判定：以落子点为中心，沿四个方向数连续同色棋子
  bool _hasFiveInRow(int col, int row, bool black) {
    const dirs = [(1, 0), (0, 1), (1, 1), (1, -1)];
    for (final (dx, dy) in dirs) {
      var count = 1;
      // 沿正负两个方向延伸计数
      for (final sign in [1, -1]) {
        var c = col + dx * sign;
        var r = row + dy * sign;
        while (_isSameStone(c, r, black)) {
          count++;
          c += dx * sign;
          r += dy * sign;
        }
      }
      if (count >= 5) return true;
    }
    return false;
  }

  /// 指定位置是否为指定颜色的已落棋子（越界视为无子）
  bool _isSameStone(int col, int row, bool black) {
    if (col < 0 || col >= _boardSize || row < 0 || row >= _boardSize) {
      return false;
    }
    final index = _moves.indexOf((col, row));
    // record 结构相等可直接 indexOf；索引奇偶即棋子颜色
    return index >= 0 && index.isEven == black;
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
      _pending = null;
      _winner = null;
    });
  }

  /// 返回设置视图：清盘后重新选择规格
  void _backToSetup() {
    setState(() {
      _moves.clear();
      _pending = null;
      _winner = null;
      _started = false;
    });
  }

  /// 悔棋：撤回最后一颗确认棋子，执子方回退
  void _undo() {
    if (_moves.isEmpty) return;
    setState(() {
      _moves.removeLast();
      _pending = null;
    });
  }

  void _onStart() {
    setState(() {
      _started = true;
      // 开启新对局后不再展示旧存档入口
      _savedState = null;
    });
  }

  /// 恢复未完成对局：从存档还原棋盘规格与落子序列
  void _resumeSaved() {
    final saved = _savedState;
    if (saved == null) return;
    setState(() {
      _boardSize = saved.boardSize;
      _moves
        ..clear()
        ..addAll(saved.moves);
      _started = true;
      _savedState = null;
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
        // 持久化完整对局状态后退出
        await GomokuStorage.save(
          GomokuGameState(
            boardSize: _boardSize,
            moves: List.of(_moves),
            savedAt: DateTime.now(),
          ),
        );
        if (mounted) Navigator.of(context).pop();
      case ConfirmResult.neutral:
        // 放弃当前对局：清除旧存档，避免下次误提示可继续
        await GomokuStorage.clear();
        if (mounted) Navigator.of(context).pop();
      case ConfirmResult.cancel:
        // 留在对局
        break;
    }
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
                // 阶段切换动画：设置视图 <-> 对局视图淡入淡出
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _started
                      ? _BoardView(
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
                      : _SetupView(
                          key: const ValueKey('setup'),
                          boardSize: _boardSize,
                          onSelect: (size) =>
                              setState(() => _boardSize = size),
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

/// 规格设置视图：恢复入口（存在存档时）+ 棋盘规格选择 + 开始按钮
class _SetupView extends StatelessWidget {
  const _SetupView({
    super.key,
    required this.boardSize,
    required this.onSelect,
    required this.onStart,
    this.savedState,
    this.onResume,
  });

  /// 当前选中路数
  final int boardSize;

  /// 选择规格回调
  final ValueChanged<int> onSelect;

  /// 点击「开始对局」回调
  final VoidCallback onStart;

  /// 未完成对局的存档；null 时不显示恢复入口
  final GomokuGameState? savedState;

  /// 点击「继续上次对局」回调
  final VoidCallback? onResume;

  /// 可选规格：15 路标准盘 / 19 路大盘
  static const List<(int, String)> _options = [
    (15, '15×15'),
    (19, '19×19'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final saved = savedState;

    return SizedBox.expand(
      child: Center(
        // 平板/桌面端限制内容宽度，居中展示
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 存在未完成对局时展示恢复入口
                if (saved != null) ...[
                  ResumeCard(
                    summary:
                        '${saved.boardSize}×${saved.boardSize} 对局 · '
                        '已落子 ${saved.moves.length} 手',
                    onTap: onResume,
                  ),
                  const SizedBox(height: 16),
                ],
                PanelCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '棋盘规格',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '标准 15 路棋盘节奏明快，19 路大盘空间更大、博弈更充分',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final (size, label) in _options)
                            OptionBlock(
                              label: label,
                              selected: size == boardSize,
                              onTap: () => onSelect(size),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: '开始对局',
                  icon: Icons.sports_esports_rounded,
                  onPressed: onStart,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 对局视图：当前执子提示 + 棋盘 + 操作按钮
class _BoardView extends StatelessWidget {
  const _BoardView({
    super.key,
    required this.boardSize,
    required this.moves,
    required this.pending,
    required this.winner,
    required this.onCellTap,
    required this.onCancelMove,
    required this.onConfirmMove,
    required this.onUndo,
    required this.onRestart,
  });

  /// 棋盘路数
  final int boardSize;

  /// 已确认落子序列
  final List<(int, int)> moves;

  /// 预选落子位置；null 表示无预选
  final (int, int)? pending;

  /// 胜方；null 表示对局进行中
  final String? winner;

  /// 点击棋盘交叉点回调
  final void Function(int col, int row) onCellTap;

  /// 点击「取消」回调：清除落子预选
  final VoidCallback onCancelMove;

  /// 点击「下棋」回调：确认落子
  final VoidCallback onConfirmMove;

  /// 点击「悔棋」回调
  final VoidCallback onUndo;

  /// 终局后点击「再来一局」回调：清盘重开
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    // 落子确认按钮仅在棋盘上有预选棋子时出现
    final hasPending = pending != null;
    // 终局后无预选、无子可悔
    final isOver = winner != null;
    final blackTurn = moves.length.isEven;

    return SizedBox.expand(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 对局中提示执子方（图标颜色对应棋子）；终局提示胜方
                TurnCard(
                  icon: Icons.circle_rounded,
                  iconColor: (isOver ? !blackTurn : blackTurn)
                      ? StoneBoard.blackStone
                      : StoneBoard.whiteStone,
                  subtitle: isOver ? '对局结束' : '当前执子',
                  title: isOver ? '$winner胜利' : (blackTurn ? '黑方' : '白方'),
                  titleKey: ValueKey(
                    isOver ? '$winner胜利' : (blackTurn ? '黑方' : '白方'),
                  ),
                ),
                const SizedBox(height: 16),
                // 棋盘占据剩余空间，正方形自适应宽高较小者
                Expanded(
                  child: Center(
                    // 五子棋无提子，落子序列奇偶即可推导颜色（先手黑）
                    // 转换为显式颜色棋子集合供通用棋盘组件绘制
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
                // 固定高度占位：确认按钮显隐时不挤压棋盘布局
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
                  // 终局：悔棋替换为再来一局，方便查看棋型后重开
                  PrimaryButton(
                    label: '再来一局',
                    icon: Icons.refresh_rounded,
                    onPressed: onRestart,
                  )
                else
                  // 对局中：无子可悔时按钮禁用（灰底不可点击）
                  PrimaryButton(
                    label: '悔棋',
                    icon: Icons.undo_rounded,
                    onPressed: moves.isEmpty ? null : onUndo,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
