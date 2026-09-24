import 'package:flutter/material.dart';

import 'package:horyx/games/word_pk/models/word_pk_entry.dart';
import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/widgets/app_text_field.dart';
import 'package:horyx/shared/widgets/page_content.dart';
import 'package:horyx/shared/widgets/panel_card.dart';
import 'package:horyx/shared/widgets/primary_button.dart';
import 'package:horyx/shared/widgets/turn_card.dart';

/// 单词PK - 对局视图
/// 受控组件：对局状态（当前输入者、单词列表）由父级持有，
/// 本组件负责展示与输入，提交经 [onSubmit] 交由父级校验处理
/// 本地对局与联机对局共用（联机通过 [inputEnabled] 控制非本人回合禁输）
class WordPkPlayView extends StatefulWidget {
  const WordPkPlayView({
    super.key,
    required this.playerCount,
    required this.currentPlayer,
    required this.entries,
    required this.onSubmit,
    this.inputEnabled = true,
    this.selfSeat,
    this.seatNames,
  });

  /// 参与人数
  final int playerCount;

  /// 当前输入者序号（从 1 开始）
  final int currentPlayer;

  /// 已验证通过的单词列表（最新置顶）
  final List<WordPkEntry> entries;

  /// 提交输入单词；返回 true 表示校验通过（组件据此清空输入框）
  final bool Function(String word) onSubmit;

  /// 是否允许输入（联机对局中非本人回合禁输；本地对局恒为 true）
  final bool inputEnabled;

  /// 自己的座位号（联机对局传入；当前输入者是自己时回合卡展示「你」）
  final int? selfSeat;

  /// 座位 -> 名字快照（联机对局传入；null 即本地对局，全部回退「玩家 N」）
  final Map<int, String>? seatNames;

  /// 座位的展示名：快照缺失或名字为空时回退「玩家 N」
  String _seatLabel(int seat) {
    final name = seatNames?[seat];
    return (name == null || name.isEmpty) ? '玩家 $seat' : name;
  }

  /// 禁输态输入框占位：联机且知道输入者名字时以「」突出；
  /// 本地对局（无快照）或名字缺失保持原占位文案
  String get _waitingHint {
    final name = seatNames?[currentPlayer];
    return (name != null && name.isNotEmpty)
        ? '等待「$name」输入…'
        : '等待玩家 $currentPlayer 输入…';
  }

  @override
  State<WordPkPlayView> createState() => _WordPkPlayViewState();
}

class _WordPkPlayViewState extends State<WordPkPlayView> {
  final _inputController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 提交输入：交由父级校验，通过后清空输入框并保持焦点
  void _submit() {
    // 提交后保持焦点，便于下一位玩家直接输入
    _focusNode.requestFocus();
    final accepted = widget.onSubmit(_inputController.text);
    if (accepted) {
      _inputController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox.expand(
      child: PageContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 当前输入者卡片（通用回合卡组件；联机时输入者是自己展示「你」）
            TurnCard(
              icon: Icons.keyboard_rounded,
              subtitle: '当前输入者',
              title: widget.currentPlayer == widget.selfSeat
                  ? '你'
                  : widget._seatLabel(widget.currentPlayer),
              titleKey: ValueKey(widget.currentPlayer),
            ),
            const SizedBox(height: 16),
            _PlayerSequence(
              playerCount: widget.playerCount,
              currentIndex: widget.currentPlayer,
              seatNames: widget.seatNames,
            ),
            const SizedBox(height: 16),
            // 单词输入行：输入框 + 提交按钮
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    focusNode: _focusNode,
                    // 非本人回合禁输（联机对局），禁用态提示等待对象
                    enabled: widget.inputEnabled,
                    // 键盘「完成」同样触发提交
                    onSubmitted: (_) => _submit(),
                    // 英文单词输入场景关闭联想与自动纠正
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    decoration: buildAppTextFieldDecoration(
                      palette,
                      hintText: widget.inputEnabled
                          ? '输入英文单词'
                          : widget._waitingHint,
                      fillColor: palette.surfaceBg,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                PrimaryButton(
                  label: '提交',
                  icon: Icons.send_rounded,
                  // 非本人回合禁用提交（联机对局）
                  onPressed: widget.inputEnabled ? _submit : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 已验证单词列表：占据剩余空间，超出滚动
            Expanded(
              child: _VerifiedWordsCard(
                entries: widget.entries,
                seatNames: widget.seatNames,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 已验证单词卡片：标题 + 数量徽标 + 单词列表（空态/滚动列表）
class _VerifiedWordsCard extends StatelessWidget {
  const _VerifiedWordsCard({required this.entries, this.seatNames});

  final List<WordPkEntry> entries;

  /// 座位 -> 名字快照（null 即本地对局，归属回退「玩家 N」）
  final Map<int, String>? seatNames;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return PanelCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '已验证单词',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              // 数量徽标随列表数据自动变化
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: palette.scaffoldBg,
                  borderRadius: BorderRadius.circular(Radii.pill),
                  border: Border.all(color: palette.stroke),
                ),
                child: Text(
                  '${entries.length} 个',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: entries.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _WordChip(
                      word: entries[index].word,
                      playerIndex: entries[index].playerIndex,
                      ownerName: seatNames?[entries[index].playerIndex],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 玩家序列：按人数排列，高亮当前输入者
class _PlayerSequence extends StatelessWidget {
  const _PlayerSequence({
    required this.playerCount,
    required this.currentIndex,
    this.seatNames,
  });

  final int playerCount;
  final int currentIndex;

  /// 座位 -> 名字快照（null 即本地对局，chip 回退「玩家 N」）
  final Map<int, String>? seatNames;

  /// 座位的展示名：快照缺失或名字为空时回退「玩家 N」
  String _label(int seat) {
    final name = seatNames?[seat];
    return (name == null || name.isEmpty) ? '玩家 $seat' : name;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int i = 1; i <= playerCount; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              // 当前输入者以描边 + 主题色文字点亮
              borderRadius: BorderRadius.circular(Radii.pill),
              color: i == currentIndex
                  ? palette.primary.withValues(alpha: 0.15)
                  : palette.surfaceBg,
              border: Border.all(
                color: i == currentIndex ? palette.primary : palette.stroke,
              ),
            ),
            child: Text(
              _label(i),
              style: TextStyle(
                color: i == currentIndex
                    ? palette.primary
                    : palette.textSecondary,
                fontSize: 12.5,
                fontWeight: i == currentIndex
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

/// 单词列表空状态
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.emoji_events_outlined,
            color: context.palette.textSecondary,
            size: 30,
          ),
          const SizedBox(height: 10),
          Text(
            '还没有验证通过的单词\n输入第一个单词开启 PK 吧',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.palette.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// 已验证单词标签
class _WordChip extends StatelessWidget {
  const _WordChip({
    required this.word,
    required this.playerIndex,
    this.ownerName,
  });

  final String word;
  final int playerIndex;

  /// 归属玩家名字（快照缺失或空串时回退「玩家 N」展示）
  final String? ownerName;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final owner = (ownerName == null || ownerName!.isEmpty)
        ? '玩家 $playerIndex'
        : ownerName!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: palette.scaffoldBg,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: palette.stroke),
      ),
      child: Row(
        children: [
          // 主题色圆点作为视觉锚点
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: palette.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              word,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            owner,
            style: TextStyle(color: palette.textSecondary, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
