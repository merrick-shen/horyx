import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/scoreboard_game_state.dart';
import '../services/scoreboard_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/option_block.dart';
import '../widgets/panel_card.dart';
import '../widgets/primary_button.dart';
import '../widgets/scoreboard/scoreboard_view.dart';

/// 计分器页面
/// 持有整场计分状态（局分、当前局比分、撤销快照），统一负责：
/// 加分与胜负判定、局/场胜利弹窗、退出确认与计分存档恢复
/// 阶段一（竖屏）：比分设置（赛制 / 每局胜利分 / 领先规则，均为数字输入）
/// 阶段二（横屏）：全屏红蓝计分板，不展示顶栏
class ScoreboardPage extends StatefulWidget {
  const ScoreboardPage({super.key});

  @override
  State<ScoreboardPage> createState() => _ScoreboardPageState();
}

class _ScoreboardPageState extends State<ScoreboardPage> {
  /// 是否处于计分阶段（横屏计分板）
  bool _playing = false;

  // ---- 比分设置（阶段一） ----

  /// 赛制：BO 几（先赢多数局者获得整场胜利）
  int _bestOf = _bestOfDefault;

  /// 每局胜利比分：本局先达到该分且满足领先分差的一方赢下本局
  int _winScore = _winScoreDefault;

  /// 领先获胜分差：0 = 到分即胜；2 = 平分后需拉开 2 分差距（乒乓球/羽毛球规则）
  int _leadBy = _leadByDefault;

  /// 数字输入框控制器（初始预填默认值，需在 dispose 释放）
  late final TextEditingController _bestOfController;
  late final TextEditingController _winScoreController;
  late final TextEditingController _leadController;

  /// 输入焦点（聚焦时品牌色描边提示输入中）
  late final FocusNode _bestOfFocus;
  late final FocusNode _winScoreFocus;
  late final FocusNode _leadFocus;

  // ---- 对局数据（阶段二） ----

  /// 红方已获胜局数（大比分）
  int _redGames = 0;

  /// 蓝方已获胜局数（大比分）
  int _blueGames = 0;

  /// 红方当前局得分（小比分）
  int _redScore = 0;

  /// 蓝方当前局得分（小比分）
  int _blueScore = 0;

  /// 撤销快照栈：每次加分前记录 [红局, 蓝局, 红分, 蓝分]，
  /// 快照法天然支持跨局撤销（含撤销已判定的局胜/场胜）
  final List<List<int>> _history = [];

  /// 当前局已分出胜负（局分已计入，等待开始下一局）
  bool _gameOver = false;

  /// 整场胜方（'红方'/'蓝方'）；null 表示比赛进行中
  String? _winner;

  /// 进入时检测到的未完成存档；恢复或开始新一场后清空展示
  ScoreboardGameState? _savedState;

  /// 各设置项默认值（输入框初始预填；清空输入时回退）
  static const int _bestOfDefault = 3;
  static const int _winScoreDefault = 21;
  static const int _leadByDefault = 2;

  /// 输入的合法范围（上限控制在两位数，避免异常大数值影响计分板排版）
  static const int _bestOfMin = 1, _bestOfMax = 31;
  static const int _winScoreMin = 1, _winScoreMax = 99;
  static const int _leadMin = 0, _leadMax = 9;

  /// 赢下整场所需局数（BO 多数局：BO3 需 2 胜，BO5 需 3 胜）
  /// 偶数 BO 也取多数局，避免总比分平局
  int get _gamesToWin => _bestOf ~/ 2 + 1;

  @override
  void initState() {
    super.initState();
    // 进入页面即锁定竖屏，避免携横屏状态进入设置视图
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    // 预填默认值，用户可直接修改而无需从空开始
    _bestOfController = TextEditingController(text: '$_bestOfDefault');
    _winScoreController = TextEditingController(text: '$_winScoreDefault');
    _leadController = TextEditingController(text: '$_leadByDefault');
    _bestOfFocus = FocusNode();
    _winScoreFocus = FocusNode();
    _leadFocus = FocusNode();
    _loadSavedState();
  }

  @override
  void dispose() {
    // 离开页面恢复竖屏，防止横屏锁定泄漏到其他页面
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _bestOfController.dispose();
    _winScoreController.dispose();
    _leadController.dispose();
    _bestOfFocus.dispose();
    _winScoreFocus.dispose();
    _leadFocus.dispose();
    super.dispose();
  }

  /// 启动时检测未完成计分，存在则在设置视图展示恢复入口
  Future<void> _loadSavedState() async {
    final state = await ScoreboardStorage.load();
    if (state != null && mounted) {
      setState(() => _savedState = state);
    }
  }

  // ---- 计分核心逻辑 ----

  /// 某方得分是否赢下当前局：到达胜利分且满足领先分差
  /// leadBy 为 0 时差值条件恒成立（到分即胜）
  bool _winsGame(int score, int opp) =>
      score >= _winScore && score - opp >= _leadBy;

  /// 点击计分区：终局锁定；本局已结束时开下一局；否则加分并判定
  void _onPanelTap(bool red) {
    if (_winner != null) return;
    if (_gameOver) {
      _startNextGame();
      return;
    }

    // 加分前快照入栈，供撤销完整回退
    _history.add([_redGames, _blueGames, _redScore, _blueScore]);

    var gameWon = false;
    var matchWon = false;
    setState(() {
      if (red) {
        _redScore++;
      } else {
        _blueScore++;
      }

      final scorer = red ? _redScore : _blueScore;
      final opp = red ? _blueScore : _redScore;
      if (_winsGame(scorer, opp)) {
        if (red) {
          _redGames++;
        } else {
          _blueGames++;
        }
        _gameOver = true;
        gameWon = true;
        if ((red ? _redGames : _blueGames) >= _gamesToWin) {
          _winner = red ? '红方' : '蓝方';
          matchWon = true;
        }
      }
    });

    // 弹窗在 setState 之后调用，避免构建期间弹 showDialog
    if (matchWon) {
      _showMatchWinDialog();
    } else if (gameWon) {
      _showGameWinDialog(red);
    }
  }

  /// 开始下一局：清空当前局比分（局分与快照保留，支持撤销跨局回退）
  void _startNextGame() {
    setState(() {
      _redScore = 0;
      _blueScore = 0;
      _gameOver = false;
    });
  }

  /// 撤销上一次加分：恢复快照，同步清除局/场结束状态
  void _undo() {
    if (_history.isEmpty) return;
    setState(() {
      final s = _history.removeLast();
      _redGames = s[0];
      _blueGames = s[1];
      _redScore = s[2];
      _blueScore = s[3];
      _gameOver = false;
      _winner = null;
    });
  }

  /// 本局胜利弹窗：下一局 / 继续查看（留在结束画面，点击计分区开下一局）
  Future<void> _showGameWinDialog(bool red) async {
    final name = red ? '红方' : '蓝方';
    final result = await showConfirmDialog(
      context,
      title: '$name赢下本局！',
      message: '本局比分 $_redScore:$_blueScore，'
          '当前大比分 $_redGames:$_blueGames（BO$_bestOf）',
      confirmLabel: '下一局',
      cancelLabel: '继续查看',
    );
    if (!mounted) return;
    if (result == ConfirmResult.confirm) {
      _startNextGame();
    }
  }

  /// 整场胜利弹窗：再来一场 / 返回设置 / 查看比分（留在终局画面）
  Future<void> _showMatchWinDialog() async {
    final winner = _winner;
    if (winner == null) return;

    final result = await showConfirmDialog(
      context,
      title: '$winner获得胜利！',
      message: '大比分 $_redGames:$_blueGames，恭喜$winner赢下整场比赛',
      confirmLabel: '再来一场',
      neutralLabel: '返回设置',
    );
    if (!mounted) return;

    switch (result) {
      case ConfirmResult.confirm:
        _restartMatch();
      case ConfirmResult.neutral:
        // 整场已结束，返回设置并清除存档（无可恢复内容）
        await ScoreboardStorage.clear();
        if (mounted) _exitPlaying();
      case ConfirmResult.cancel:
        // 留在终局画面查看比分，撤销可回退终局
        break;
    }
  }

  /// 再来一场：保持当前配置，比分与历史全部重置
  void _restartMatch() {
    setState(() {
      _redGames = 0;
      _blueGames = 0;
      _redScore = 0;
      _blueScore = 0;
      _gameOver = false;
      _winner = null;
      _history.clear();
    });
  }

  // ---- 阶段切换与存档 ----

  /// 开始计分：重置为新一场，锁定横屏并切换到计分板
  void _startPlaying() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    setState(() {
      _redGames = 0;
      _blueGames = 0;
      _redScore = 0;
      _blueScore = 0;
      _gameOver = false;
      _winner = null;
      _history.clear();
      _playing = true;
      // 开启新一场后不再展示旧存档恢复入口
      _savedState = null;
    });
  }

  /// 退出计分请求：有计分动作且未终局时弹三选项确认（保存退出/不保存退出/取消）
  /// 未计分或已终局时无进行中内容，直接回设置
  Future<void> _requestExit() async {
    if (_history.isEmpty || _winner != null) {
      _exitPlaying();
      return;
    }

    final result = await showConfirmDialog(
      context,
      title: '退出计分？',
      message: '保存并退出后，下次进入可从当前比分继续',
      confirmLabel: '保存并退出',
      neutralLabel: '不保存并退出',
    );
    if (!mounted) return;

    switch (result) {
      case ConfirmResult.confirm:
        // 持久化完整状态（含撤销栈）后回设置
        await ScoreboardStorage.save(
          ScoreboardGameState(
            bestOf: _bestOf,
            winScore: _winScore,
            leadBy: _leadBy,
            redGames: _redGames,
            blueGames: _blueGames,
            redScore: _redScore,
            blueScore: _blueScore,
            history: List.of(_history),
            savedAt: DateTime.now(),
          ),
        );
        if (mounted) _exitPlaying();
      case ConfirmResult.neutral:
        // 放弃当前计分：清除旧存档，避免下次误提示可继续
        await ScoreboardStorage.clear();
        if (mounted) _exitPlaying();
      case ConfirmResult.cancel:
        // 留在计分板
        break;
    }
  }

  /// 退出计分：恢复竖屏并回到设置视图，刷新恢复入口（保存退出后需展示）
  void _exitPlaying() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    setState(() => _playing = false);
    _loadSavedState();
  }

  /// 恢复未完成计分：还原配置、比分与撤销栈，设置输入框同步显示
  void _resumeSaved() {
    final saved = _savedState;
    if (saved == null) return;

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    setState(() {
      _bestOf = saved.bestOf;
      _winScore = saved.winScore;
      _leadBy = saved.leadBy;
      _redGames = saved.redGames;
      _blueGames = saved.blueGames;
      _redScore = saved.redScore;
      _blueScore = saved.blueScore;
      _history
        ..clear()
        ..addAll(saved.history);
      _gameOver = false;
      _winner = null;
      _savedState = null;
      _playing = true;
      // 设置输入框同步为恢复的配置，退出回设置时展示一致
      _bestOfController.text = '${saved.bestOf}';
      _winScoreController.text = '${saved.winScore}';
      _leadController.text = '${saved.leadBy}';
    });
  }

  @override
  Widget build(BuildContext context) {
    // 计分阶段：无顶栏全屏；拦截系统返回走退出确认流程
    if (_playing) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _requestExit();
        },
        child: ScoreboardView(
          bestOf: _bestOf,
          redGames: _redGames,
          blueGames: _blueGames,
          redScore: _redScore,
          blueScore: _blueScore,
          gameOver: _gameOver,
          winner: _winner,
          onRedTap: () => _onPanelTap(true),
          onBlueTap: () => _onPanelTap(false),
          // 无计分记录时撤销禁用（灰底不可点击）
          onUndo: _history.isEmpty ? null : _undo,
          onExit: _requestExit,
        ),
      );
    }

    // 设置阶段：顶栏 + 比分设置面板
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppTopBar(
              title: '计分器',
              leading: IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: context.palette.textPrimary,
                  size: 20,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Expanded(
              child: Center(
                // 平板/横屏窗口下限制内容宽度
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  // 面板较多，允许小屏设备滚动
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 存在未完成计分时展示恢复入口
                        if (_savedState != null) ...[
                          _ResumeCard(
                            state: _savedState!,
                            onTap: _resumeSaved,
                          ),
                          const SizedBox(height: 16),
                        ],
                        _buildSettingPanel(
                          title: '赛制',
                          subtitle: '先赢得多数局数的一方获得整场胜利，输入局数（$_bestOfMin-$_bestOfMax）',
                          child: NumberOptionBlock(
                            key: const Key('bestOfInput'),
                            controller: _bestOfController,
                            focusNode: _bestOfFocus,
                            hintText: '输入局数',
                            min: _bestOfMin,
                            max: _bestOfMax,
                            onValid: (v) => setState(() => _bestOf = v),
                            onCleared: () =>
                                setState(() => _bestOf = _bestOfDefault),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSettingPanel(
                          title: '每局胜利比分',
                          subtitle: '每局先达到该比分的一方赢下本局，输入分值（$_winScoreMin-$_winScoreMax）',
                          child: NumberOptionBlock(
                            key: const Key('winScoreInput'),
                            controller: _winScoreController,
                            focusNode: _winScoreFocus,
                            hintText: '输入分值',
                            min: _winScoreMin,
                            max: _winScoreMax,
                            onValid: (v) => setState(() => _winScore = v),
                            onCleared: () =>
                                setState(() => _winScore = _winScoreDefault),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSettingPanel(
                          title: '领先获胜规则',
                          subtitle: '到达局点后需拉开该分差才能分出胜负，0 为到分即胜（$_leadMin-$_leadMax）',
                          child: NumberOptionBlock(
                            key: const Key('leadInput'),
                            controller: _leadController,
                            focusNode: _leadFocus,
                            hintText: '输入分差',
                            min: _leadMin,
                            max: _leadMax,
                            onValid: (v) => setState(() => _leadBy = v),
                            onCleared: () =>
                                setState(() => _leadBy = _leadByDefault),
                          ),
                        ),
                        const SizedBox(height: 24),
                        PrimaryButton(
                          label: '开始计分',
                          icon: Icons.sports_score_rounded,
                          onPressed: _startPlaying,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建设置面板：标题 + 说明 + 输入块
  Widget _buildSettingPanel({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final palette = context.palette;

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

/// 继续上次计分入口卡片（样式与五子棋恢复入口一致）
class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.state, required this.onTap});

  final ScoreboardGameState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // 品牌色淡底 + 描边，与普通卡片区分，突出「可继续」
          color: palette.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: palette.primary.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.play_circle_fill_rounded,
              color: palette.primary,
              size: 34,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '继续上次计分',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'BO${state.bestOf} · 大比分 ${state.redGames}:${state.blueGames}'
                    ' · 当前局 ${state.redScore}:${state.blueScore}',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: palette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
