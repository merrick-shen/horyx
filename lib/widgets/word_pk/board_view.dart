import 'package:flutter/material.dart';

import '../../models/word_entry.dart';
import '../../theme/app_theme.dart';
import '../primary_button.dart';
import '../turn_card.dart';

/// 单词PK - 对局视图
/// 受控组件：对局状态（当前输入者、单词列表）由父级 WordPkPage 持有，
/// 本组件负责展示与输入，提交经 [onSubmit] 交由父级校验处理
class WordPkBoardView extends StatefulWidget {
  const WordPkBoardView({
    super.key,
    required this.playerCount,
    required this.currentPlayer,
    required this.entries,
    required this.onSubmit,
  });

  /// 参与人数
  final int playerCount;

  /// 当前输入者序号（从 1 开始）
  final int currentPlayer;

  /// 已验证通过的单词列表（最新置顶）
  final List<WordEntry> entries;

  /// 提交输入单词；返回 true 表示校验通过（组件据此清空输入框）
  final bool Function(String word) onSubmit;

  @override
  State<WordPkBoardView> createState() => _WordPkBoardViewState();
}

class _WordPkBoardViewState extends State<WordPkBoardView> {
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
      child: Center(
        // 平板/桌面端限制内容宽度，居中展示
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 当前输入者卡片（通用回合卡组件）
                TurnCard(
                  icon: Icons.keyboard_rounded,
                  subtitle: '当前输入者',
                  title: '玩家 ${widget.currentPlayer}',
                  titleKey: ValueKey(widget.currentPlayer),
                ),
                const SizedBox(height: 16),
                _PlayerSequence(
                  playerCount: widget.playerCount,
                  currentIndex: widget.currentPlayer,
                ),
                const SizedBox(height: 16),
                // 单词输入行：输入框 + 提交按钮
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        focusNode: _focusNode,
                        // 键盘「完成」同样触发提交
                        onSubmitted: (_) => _submit(),
                        // 英文单词输入场景关闭联想与自动纠正
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: '输入英文单词',
                          hintStyle: TextStyle(
                            color: palette.textSecondary,
                          ),
                          filled: true,
                          fillColor: palette.surfaceBg,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: palette.stroke,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: palette.primary,
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    PrimaryButton(
                      label: '提交',
                      icon: Icons.send_rounded,
                      onPressed: _submit,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 已验证单词列表：占据剩余空间，超出滚动
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    decoration: BoxDecoration(
                      color: palette.surfaceBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: palette.stroke),
                    ),
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
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: palette.stroke),
                              ),
                              child: Text(
                                '${widget.entries.length} 个',
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
                          child: widget.entries.isEmpty
                              ? const _EmptyState()
                              : ListView.separated(
                                  padding: EdgeInsets.zero,
                                  itemCount: widget.entries.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) => _WordChip(
                                    word: widget.entries[index].word,
                                    playerIndex:
                                        widget.entries[index].playerIndex,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 玩家序列：按人数排列，高亮当前输入者
class _PlayerSequence extends StatelessWidget {
  const _PlayerSequence({
    required this.playerCount,
    required this.currentIndex,
  });

  final int playerCount;
  final int currentIndex;

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
              // 当前输入者以描边 + 品牌色文字点亮
              borderRadius: BorderRadius.circular(999),
              color: i == currentIndex
                  ? palette.primary.withValues(alpha: 0.15)
                  : palette.surfaceBg,
              border: Border.all(
                color: i == currentIndex ? palette.primary : palette.stroke,
              ),
            ),
            child: Text(
              '玩家 $i',
              style: TextStyle(
                color: i == currentIndex
                    ? palette.primary
                    : palette.textSecondary,
                fontSize: 12.5,
                fontWeight:
                    i == currentIndex ? FontWeight.w700 : FontWeight.w500,
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
  const _WordChip({required this.word, required this.playerIndex});

  final String word;
  final int playerIndex;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: palette.scaffoldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.stroke),
      ),
      child: Row(
        children: [
          // 品牌色圆点作为视觉锚点
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
            '玩家 $playerIndex',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}
