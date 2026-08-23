import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/games/scoreboard_game_state.dart';
import '../../services/storage/scoreboard_storage.dart';
import '../../widgets/common/app_top_bar.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/scoreboard/scoreboard_view.dart';
import '../../widgets/scoreboard/setup_view.dart';

/// 计分器页面
/// 持有整场计分状态（局分、当前局比分、撤销快照），统一负责：
/// 加分与胜负判定、局/场胜利弹窗、退出确认与计分存档恢复
/// 阶段一（竖屏）：比分设置（赛制 / 每局胜利分 / 领先规则）——见 ScoreboardSetupView
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
  /// 默认值与设置视图保持同源；实际值在开始计分/恢复存档时由视图上报
  int _bestOf = ScoreboardSetupView.bestOfDefault;

  /// 每局胜利比分：本局先达到该分且满足领先分差的一方赢下本局
  int _winScore = ScoreboardSetupView.winScoreDefault;

  /// 领先获胜分差：0 = 到分即胜；2 = 平分后需拉开 2 分差距（乒乓球/羽毛球规则）
  int _leadBy = ScoreboardSetupView.leadByDefault;

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

  /// 赢下整场所需局数（BO 多数局：BO3 需 2 胜，BO5 需 3 胜）
  /// 偶数 BO 也取多数局，避免总比分平局
  int get _gamesToWin => _bestOf ~/ 2 + 1;

  @override
  void initState() {
    super.initState();
    // 进入页面即锁定竖屏，避免携横屏状态进入设置视图
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _loadSavedState();
  }

  @override
  void dispose() {
    // 离开页面恢复竖屏，防止横屏锁定泄漏到其他页面
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
      // 整场已分胜负，立即清除存档：无论后续选哪条路径（再来一场/返回设置/查看比分），
      // 都不能让已结束的比分被当作进行中对局恢复（与围棋终局处理一致）
      ScoreboardStorage.clear();
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

  /// 开始计分：记录设置视图上报的配置，重置为新一场，锁定横屏并切换到计分板
  void _startPlaying(int bestOf, int winScore, int leadBy) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    setState(() {
      _bestOf = bestOf;
      _winScore = winScore;
      _leadBy = leadBy;
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

  /// 恢复未完成计分：还原配置、比分与撤销栈
  /// 输入框无需手动同步：回到设置阶段时视图以当前配置重建，自动展示一致
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

    // 设置阶段：顶栏 + 比分设置视图
    // 配置在设置视图内部维护，点击开始时一次性上报；
    // 恢复存档或退出计分回到设置时以当前生效配置重建，输入框展示一致
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppTopBar(title: '计分器', showBack: true),
            Expanded(
              child: ScoreboardSetupView(
                initialBestOf: _bestOf,
                initialWinScore: _winScore,
                initialLeadBy: _leadBy,
                savedState: _savedState,
                onResume: _resumeSaved,
                onStart: _startPlaying,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
