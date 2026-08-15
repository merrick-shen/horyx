import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/option_block.dart';
import '../widgets/panel_card.dart';
import '../widgets/primary_button.dart';
import '../widgets/scoreboard/scoreboard_view.dart';

/// 计分器页面
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

  /// 每局胜利比分：本局先达到该分的一方赢下本局
  /// 计分交互开发阶段接入胜负判定，当前静态结构阶段暂无读取处
  // ignore: unused_field
  int _winScore = _winScoreDefault;

  /// 领先获胜分差：0 = 到分即胜；2 = 平分后需拉开 2 分差距（乒乓球/羽毛球规则）
  /// 计分交互开发阶段接入胜负判定，当前静态结构阶段暂无读取处
  // ignore: unused_field
  int _leadBy = _leadByDefault;

  /// 数字输入框控制器（初始预填默认值，需在 dispose 释放）
  late final TextEditingController _bestOfController;
  late final TextEditingController _winScoreController;
  late final TextEditingController _leadController;

  /// 输入焦点（聚焦时品牌色描边提示输入中）
  late final FocusNode _bestOfFocus;
  late final FocusNode _winScoreFocus;
  late final FocusNode _leadFocus;

  // ---- 对局数据（阶段二，静态结构阶段为初始值） ----

  /// 红方已获胜局数（大比分）
  final int _redGames = 0;

  /// 蓝方已获胜局数（大比分）
  final int _blueGames = 0;

  /// 红方当前局得分（小比分）
  final int _redScore = 0;

  /// 蓝方当前局得分（小比分）
  final int _blueScore = 0;

  /// 各设置项默认值（输入框初始预填；清空输入时回退）
  static const int _bestOfDefault = 3;
  static const int _winScoreDefault = 21;
  static const int _leadByDefault = 2;

  /// 输入的合法范围（上限控制在两位数，避免异常大数值影响计分板排版）
  static const int _bestOfMin = 1, _bestOfMax = 31;
  static const int _winScoreMin = 1, _winScoreMax = 99;
  static const int _leadMin = 0, _leadMax = 9;

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

  /// 开始计分：锁定横屏并切换到计分板
  void _startPlaying() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    setState(() => _playing = true);
  }

  /// 退出计分：恢复竖屏并回到设置视图
  void _exitPlaying() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    setState(() => _playing = false);
  }

  @override
  Widget build(BuildContext context) {
    // 计分阶段：无顶栏全屏；拦截系统返回 → 回设置视图并恢复竖屏
    if (_playing) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _exitPlaying();
        },
        child: ScoreboardView(
          bestOf: _bestOf,
          redGames: _redGames,
          blueGames: _blueGames,
          redScore: _redScore,
          blueScore: _blueScore,
          // 撤销依赖计分历史，交互开发阶段接入
          onUndo: null,
          onExit: _exitPlaying,
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
