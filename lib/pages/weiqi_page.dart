import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/option_block.dart';
import '../widgets/panel_card.dart';
import '../widgets/primary_button.dart';
import '../widgets/stone_board.dart';
import '../widgets/turn_card.dart';

/// 围棋游戏页
/// 持有对局状态（着手序列、预选、执子方），统一负责：
/// 落子确认、虚手轮换、悔棋回退与页面退出
/// 当前阶段为静态 UI 骨架：不含气/提子/打劫等规则判定与终局数子，
/// 也不含存档功能（含退出确认弹窗），均留待后续阶段接入
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

  /// 已完成的着手序列（落子与虚手按发生顺序记录）
  final List<_Move> _moves = [];

  /// 预选落子位置；null 表示无预选
  (int, int)? _pending;

  /// 当前执黑方（黑先；落子与虚手后均轮换）
  /// 不能按落子数奇偶推导：虚手轮换执子但不增加落子数
  bool _blackToMove = true;

  /// 黑方提子数（吃掉的白子）；静态阶段无提子规则恒为 0，提子逻辑接入后更新
  final int _blackCaptures = 0;

  /// 白方提子数（吃掉的黑子）；静态阶段无提子规则恒为 0
  final int _whiteCaptures = 0;

  /// 点击棋盘交叉点：已有棋子的点不可选，其余更新预选
  void _onCellTap(int col, int row) {
    final occupied = _moves.any(
      (m) => !m.pass && m.col == col && m.row == row,
    );
    if (occupied) return;
    setState(() => _pending = (col, row));
  }

  /// 取消预选：预选棋子消失
  void _cancelMove() {
    setState(() => _pending = null);
  }

  /// 确认落子：预选棋子转正式，执子方轮换
  /// 静态阶段无规则校验（气/提子/禁着点判定在后续阶段接入）
  void _confirmMove() {
    final selected = _pending;
    if (selected == null) return;
    final (col, row) = selected;
    setState(() {
      _moves.add((col: col, row: row, black: _blackToMove, pass: false));
      _pending = null;
      _blackToMove = !_blackToMove;
    });
  }

  /// 虚手（停一手）：不落子仅轮换执子方，记入着手序列供悔棋回退
  /// 连续两次虚手终局的判定在终局阶段接入
  void _pass() {
    setState(() {
      _moves.add((col: -1, row: -1, black: _blackToMove, pass: true));
      _pending = null;
      _blackToMove = !_blackToMove;
    });
  }

  /// 悔棋：撤回最后一步着手（落子或虚手），执子方同步回退
  void _undo() {
    if (_moves.isEmpty) return;
    setState(() {
      _moves.removeLast();
      _pending = null;
      _blackToMove = !_blackToMove;
    });
  }

  void _onStart() {
    setState(() => _started = true);
  }

  /// 退出请求：直接返回主页
  /// 对局中退出的确认弹窗随存档功能一起在后续阶段引入
  void _requestExit() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppTopBar(
              title: '围棋',
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
                        blackToMove: _blackToMove,
                        blackCaptures: _blackCaptures,
                        whiteCaptures: _whiteCaptures,
                        onCellTap: _onCellTap,
                        onCancelMove: _cancelMove,
                        onConfirmMove: _confirmMove,
                        onUndo: _undo,
                        onPass: _pass,
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

  /// 可选规格：9 路小盘 / 13 路中盘 / 19 路标准盘
  static const List<(int, String)> _options = [
    (9, '9×9'),
    (13, '13×13'),
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
                        '9 路小盘节奏轻快，13 路攻防均衡，19 路为标准对局盘',
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

/// 对局视图：执子提示 + 提子数面板 + 棋盘 + 操作按钮
class _BoardView extends StatelessWidget {
  const _BoardView({
    super.key,
    required this.boardSize,
    required this.moves,
    required this.pending,
    required this.blackToMove,
    required this.blackCaptures,
    required this.whiteCaptures,
    required this.onCellTap,
    required this.onCancelMove,
    required this.onConfirmMove,
    required this.onUndo,
    required this.onPass,
  });

  /// 棋盘路数
  final int boardSize;

  /// 已完成的着手序列（含虚手记录）
  final List<_Move> moves;

  /// 预选落子位置；null 表示无预选
  final (int, int)? pending;

  /// 当前执黑方
  final bool blackToMove;

  /// 黑方提子数
  final int blackCaptures;

  /// 白方提子数
  final int whiteCaptures;

  /// 点击棋盘交叉点回调
  final void Function(int col, int row) onCellTap;

  /// 点击「取消」回调：清除落子预选
  final VoidCallback onCancelMove;

  /// 点击「下棋」回调：确认落子
  final VoidCallback onConfirmMove;

  /// 点击「悔棋」回调
  final VoidCallback onUndo;

  /// 点击「虚手」回调：停一手轮换执子
  final VoidCallback onPass;

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
                // 对局中提示执子方（图标颜色对应棋子）
                TurnCard(
                  icon: Icons.circle_rounded,
                  iconColor: blackToMove
                      ? StoneBoard.blackStone
                      : StoneBoard.whiteStone,
                  subtitle: '当前执子',
                  title: blackToMove ? '黑方' : '白方',
                  titleKey: ValueKey(blackToMove ? '黑方' : '白方'),
                ),
                const SizedBox(height: 12),
                // 双方提子数面板（围棋特色信息，静态阶段恒为 0）
                Row(
                  children: [
                    Expanded(
                      child: _CaptureCard(
                        label: '黑方提子',
                        count: blackCaptures,
                        stoneColor: StoneBoard.blackStone,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _CaptureCard(
                        label: '白方提子',
                        count: whiteCaptures,
                        stoneColor: StoneBoard.whiteStone,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 棋盘占据剩余空间，正方形自适应宽高较小者
                Expanded(
                  child: Center(
                    // 虚手记录无棋子，过滤后仅落子参与绘制
                    child: StoneBoard(
                      size: boardSize,
                      stones: [
                        for (final m in moves)
                          if (!m.pass) (m.col, m.row, m.black),
                      ],
                      pending: pending == null
                          ? null
                          : (pending!.$1, pending!.$2, blackToMove),
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
                // 对局操作：虚手（停一手）+ 悔棋；无着手可悔时悔棋禁用
                Row(
                  children: [
                    Expanded(
                      child: PrimaryButton(
                        label: '虚手',
                        icon: Icons.hourglass_bottom_rounded,
                        outlined: true,
                        onPressed: onPass,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        label: '悔棋',
                        icon: Icons.undo_rounded,
                        onPressed: moves.isEmpty ? null : onUndo,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 提子数卡片：棋子色圆点 + 方名 + 提子数
class _CaptureCard extends StatelessWidget {
  const _CaptureCard({
    required this.label,
    required this.count,
    required this.stoneColor,
  });

  /// 方名（如「黑方提子」）
  final String label;

  /// 提子数
  final int count;

  /// 对应棋子颜色（圆点展示）
  final Color stoneColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: palette.surfaceBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.stroke),
      ),
      child: Row(
        children: [
          // 棋子圆点：描边保证深浅主题下轮廓清晰（与棋盘棋子一致）
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: stoneColor,
              border: Border.all(color: palette.stroke),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12.5,
            ),
          ),
          const Spacer(),
          Text(
            '$count',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
