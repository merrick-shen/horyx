import 'package:flutter/material.dart';

import '../../models/games/scoreboard_game_state.dart';
import '../../theme/app_theme.dart';
import '../common/option_block.dart';
import '../common/panel_card.dart';
import '../common/primary_button.dart';
import '../common/resume_card.dart';

/// 计分器 - 比分设置视图
/// 顶部展示未完成计分的恢复入口（存在存档时），
/// 下方为赛制 / 每局胜利比分 / 领先规则的数字输入与开始按钮；
/// 三项配置由视图内部维护，点击「开始计分」时一次性上报页面
class ScoreboardSetupView extends StatefulWidget {
  const ScoreboardSetupView({
    super.key,
    required this.onStart,
    this.initialBestOf = ScoreboardSetupView.bestOfDefault,
    this.initialWinScore = ScoreboardSetupView.winScoreDefault,
    this.initialLeadBy = ScoreboardSetupView.leadByDefault,
    this.savedState,
    this.onResume,
  });

  /// 点击「开始计分」回调，参数为（赛制局数, 每局胜利比分, 领先分差）
  final void Function(int bestOf, int winScore, int leadBy) onStart;

  /// 输入框初始预填值（恢复存档或退出计分后回到设置时，
  /// 页面传入当前生效配置，保持输入框与实际计分规则一致）
  final int initialBestOf;
  final int initialWinScore;
  final int initialLeadBy;

  /// 未完成计分的存档；null 时不显示恢复入口
  final ScoreboardGameState? savedState;

  /// 点击「继续上次计分」回调
  final VoidCallback? onResume;

  /// 各设置项默认值（输入框预填；清空输入时回退）
  static const int bestOfDefault = 3;
  static const int winScoreDefault = 21;
  static const int leadByDefault = 2;

  @override
  State<ScoreboardSetupView> createState() => _ScoreboardSetupViewState();
}

class _ScoreboardSetupViewState extends State<ScoreboardSetupView> {
  /// 输入的合法范围（上限控制在两位数，避免异常大数值影响计分板排版）
  static const int _bestOfMin = 1, _bestOfMax = 31;
  static const int _winScoreMin = 1, _winScoreMax = 99;
  static const int _leadMin = 0, _leadMax = 9;

  /// 当前生效的三项配置：输入合法值时即时更新，开始计分时上报；
  /// 非法输入（如超范围）保持上次生效值，与红边提示语义一致
  late int _bestOf;
  late int _winScore;
  late int _leadBy;

  /// 数字输入框控制器（初始预填当前配置，需在 dispose 释放）
  late final TextEditingController _bestOfController;
  late final TextEditingController _winScoreController;
  late final TextEditingController _leadController;

  /// 输入焦点（聚焦时品牌色描边提示输入中）
  late final FocusNode _bestOfFocus;
  late final FocusNode _winScoreFocus;
  late final FocusNode _leadFocus;

  @override
  void initState() {
    super.initState();
    _bestOf = widget.initialBestOf;
    _winScore = widget.initialWinScore;
    _leadBy = widget.initialLeadBy;
    _bestOfController = TextEditingController(text: '${widget.initialBestOf}');
    _winScoreController =
        TextEditingController(text: '${widget.initialWinScore}');
    _leadController = TextEditingController(text: '${widget.initialLeadBy}');
    _bestOfFocus = FocusNode();
    _winScoreFocus = FocusNode();
    _leadFocus = FocusNode();
  }

  @override
  void dispose() {
    _bestOfController.dispose();
    _winScoreController.dispose();
    _leadController.dispose();
    _bestOfFocus.dispose();
    _winScoreFocus.dispose();
    _leadFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.savedState;

    return SizedBox.expand(
      child: Center(
        // 平板/桌面端限制内容宽度，居中展示
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          // 面板较多，允许小屏设备滚动
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 存在未完成计分时展示恢复入口
                if (saved != null) ...[
                  ResumeCard(
                    title: '继续上次计分',
                    summary:
                        'BO${saved.bestOf} · '
                        '大比分 ${saved.redGames}:${saved.blueGames}'
                        ' · 当前局 ${saved.redScore}:${saved.blueScore}',
                    onTap: widget.onResume,
                  ),
                  const SizedBox(height: 16),
                ],
                _buildSettingPanel(
                  title: '赛制',
                  subtitle:
                      '先赢得多数局数的一方获得整场胜利，输入局数（$_bestOfMin-$_bestOfMax）',
                  child: NumberOptionBlock(
                    key: const Key('bestOfInput'),
                    controller: _bestOfController,
                    focusNode: _bestOfFocus,
                    hintText: '输入局数',
                    min: _bestOfMin,
                    max: _bestOfMax,
                    onValid: (v) => setState(() => _bestOf = v),
                    onCleared: () => setState(
                      () => _bestOf = ScoreboardSetupView.bestOfDefault,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildSettingPanel(
                  title: '每局胜利比分',
                  subtitle:
                      '每局先达到该比分的一方赢下本局，输入分值（$_winScoreMin-$_winScoreMax）',
                  child: NumberOptionBlock(
                    key: const Key('winScoreInput'),
                    controller: _winScoreController,
                    focusNode: _winScoreFocus,
                    hintText: '输入分值',
                    min: _winScoreMin,
                    max: _winScoreMax,
                    onValid: (v) => setState(() => _winScore = v),
                    onCleared: () => setState(
                      () => _winScore = ScoreboardSetupView.winScoreDefault,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildSettingPanel(
                  title: '领先获胜规则',
                  subtitle:
                      '到达局点后需拉开该分差才能分出胜负，0 为到分即胜（$_leadMin-$_leadMax）',
                  child: NumberOptionBlock(
                    key: const Key('leadInput'),
                    controller: _leadController,
                    focusNode: _leadFocus,
                    hintText: '输入分差',
                    min: _leadMin,
                    max: _leadMax,
                    onValid: (v) => setState(() => _leadBy = v),
                    onCleared: () => setState(
                      () => _leadBy = ScoreboardSetupView.leadByDefault,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: '开始计分',
                  icon: Icons.sports_score_rounded,
                  // 上报当前生效配置（非法输入不生效，保持上次值）
                  onPressed: () => widget.onStart(_bestOf, _winScore, _leadBy),
                ),
              ],
            ),
          ),
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
