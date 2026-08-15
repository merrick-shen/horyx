import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/gomoku/gomoku_board.dart';
import '../widgets/option_block.dart';
import '../widgets/panel_card.dart';
import '../widgets/primary_button.dart';
import '../widgets/turn_card.dart';

/// 五子棋游戏页（静态阶段）
/// 当前仅含规格选择与对局界面布局，落子与胜负玩法待开发
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

  /// 点击棋盘交叉点：已有棋子的点不可选，其余更新预选
  void _onCellTap(int col, int row) {
    if (_moves.contains((col, row))) return;
    setState(() => _pending = (col, row));
  }

  /// 取消预选：预选棋子消失
  void _cancelMove() {
    setState(() => _pending = null);
  }

  /// 确认落子：预选棋子转正式，执子方轮换
  void _confirmMove() {
    final selected = _pending;
    if (selected == null) return;
    setState(() {
      _moves.add(selected);
      _pending = null;
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
    setState(() => _started = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppTopBar(
              title: '五子棋',
              // 静态阶段无对局状态，直接返回；玩法接入后再加退出确认
              leading: IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: context.palette.textPrimary,
                  size: 20,
                ),
                onPressed: () => Navigator.of(context).pop(),
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
                        onCellTap: _onCellTap,
                        onCancelMove: _cancelMove,
                        onConfirmMove: _confirmMove,
                        onUndo: _undo,
                      )
                    : _SetupView(
                        key: const ValueKey('setup'),
                        boardSize: _boardSize,
                        onSelect: (size) =>
                            setState(() => _boardSize = size),
                        onStart: _onStart,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 规格设置视图：棋盘规格选择 + 开始按钮
class _SetupView extends StatelessWidget {
  const _SetupView({
    super.key,
    required this.boardSize,
    required this.onSelect,
    required this.onStart,
  });

  /// 当前选中路数
  final int boardSize;

  /// 选择规格回调
  final ValueChanged<int> onSelect;

  /// 点击「开始对局」回调
  final VoidCallback onStart;

  /// 可选规格：15 路标准盘 / 19 路大盘
  static const List<(int, String)> _options = [
    (15, '15×15'),
    (19, '19×19'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

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
    required this.onCellTap,
    required this.onCancelMove,
    required this.onConfirmMove,
    required this.onUndo,
  });

  /// 棋盘路数
  final int boardSize;

  /// 已确认落子序列
  final List<(int, int)> moves;

  /// 预选落子位置；null 表示无预选
  final (int, int)? pending;

  /// 点击棋盘交叉点回调
  final void Function(int col, int row) onCellTap;

  /// 点击「取消」回调：清除落子预选
  final VoidCallback onCancelMove;

  /// 点击「下棋」回调：确认落子
  final VoidCallback onConfirmMove;

  /// 点击「悔棋」回调
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    // 落子确认按钮仅在棋盘上有预选棋子时出现
    final hasPending = pending != null;

    return SizedBox.expand(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 执子方轮换时淡入淡出提示，图标颜色对应执子方棋子
                TurnCard(
                  icon: Icons.circle_rounded,
                  iconColor: moves.length.isEven
                      ? GomokuBoard.blackStone
                      : GomokuBoard.whiteStone,
                  subtitle: '当前执子',
                  title: moves.length.isEven ? '黑方' : '白方',
                  titleKey: ValueKey(moves.length.isEven ? '黑方' : '白方'),
                ),
                const SizedBox(height: 16),
                // 棋盘占据剩余空间，正方形自适应宽高较小者
                Expanded(
                  child: Center(
                    child: GomokuBoard(
                      size: boardSize,
                      stones: moves,
                      pending: pending,
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
                // 无棋子可悔时按钮禁用（灰底不可点击）
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
