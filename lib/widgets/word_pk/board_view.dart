import 'package:flutter/material.dart';

import '../../models/word_entry.dart';
import '../../services/word_validator.dart';
import '../../theme/app_theme.dart';
import '../primary_button.dart';

/// 单词PK - 对局视图
/// 完整提交流程：空值/格式检查 → 重复检测 → 真实性验证 → 入列并轮换输入者
class WordPkBoardView extends StatefulWidget {
  const WordPkBoardView({super.key, required this.playerCount});

  /// 参与人数（由设置视图传入）
  final int playerCount;

  @override
  State<WordPkBoardView> createState() => _WordPkBoardViewState();
}

class _WordPkBoardViewState extends State<WordPkBoardView> {
  final _inputController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  /// 已验证通过的单词列表
  final List<WordEntry> _entries = [];

  /// 当前输入者序号（从 1 开始）
  int _currentPlayer = 1;

  @override
  void dispose() {
    _inputController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 提交输入：按「格式 → 重复 → 真实性」顺序校验
  void _submit() {
    final raw = _inputController.text.trim();

    // 提交后保持焦点，便于下一位玩家直接输入
    _focusNode.requestFocus();

    if (raw.isEmpty) {
      _showHint('请输入英文单词');
      return;
    }
    // 仅允许纯英文字母，提前拦截中文、数字、空格等输入
    if (!RegExp(r'^[A-Za-z]+$').hasMatch(raw)) {
      _showHint('单词只能由英文字母组成');
      return;
    }
    // 统一小写后参与重复比较，忽略大小写差异
    final word = raw.toLowerCase();
    if (_entries.any((e) => e.word == word)) {
      _showHint('单词已重复');
      return;
    }
    if (!WordValidator.isValid(word)) {
      _showHint('不是有效的英文单词');
      return;
    }

    // 全部校验通过：入列并轮换至下一位输入者
    setState(() {
      _entries.add(WordEntry(word: word, playerIndex: _currentPlayer));
      _currentPlayer = _currentPlayer % widget.playerCount + 1;
    });
    _inputController.clear();
    // 新输入成功时清除遗留的错误提示，避免信息干扰
    _hideHint();
    _scrollToLatest();
  }

  /// 展示错误/引导提示
  /// 按需求需手动关闭（不自动消失），避免玩家漏看提示
  void _showHint(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(days: 1),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '知道了',
            onPressed: _hideHint,
          ),
        ),
      );
  }

  void _hideHint() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  /// 新单词入列后滚动到列表底部，保证最新单词可见
  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
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
                _CurrentPlayerCard(playerIndex: _currentPlayer),
                const SizedBox(height: 16),
                _PlayerSequence(
                  playerCount: widget.playerCount,
                  currentIndex: _currentPlayer,
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
                          hintStyle: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceBg,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.stroke,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
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
                      color: AppColors.surfaceBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.stroke),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '已验证单词',
                              style: TextStyle(
                                color: AppColors.textPrimary,
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
                                color: AppColors.scaffoldBg,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: AppColors.stroke),
                              ),
                              child: Text(
                                '${_entries.length} 个',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _entries.isEmpty
                              ? const _EmptyState()
                              : ListView.separated(
                                  controller: _scrollController,
                                  padding: EdgeInsets.zero,
                                  itemCount: _entries.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) => _WordChip(
                                    word: _entries[index].word,
                                    playerIndex: _entries[index].playerIndex,
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

/// 当前输入者卡片
class _CurrentPlayerCard extends StatelessWidget {
  const _CurrentPlayerCard({required this.playerIndex});

  /// 当前输入者序号（从 1 开始）
  final int playerIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: AppColors.brandGradient),
        borderRadius: BorderRadius.circular(20),
        // 品牌色光晕强调「轮到谁」
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.keyboard_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 半透明白色小字，叠在渐变底上仍清晰
              Text(
                '当前输入者',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              // 玩家切换时淡入淡出，强化轮换感知
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  '玩家 $playerIndex',
                  key: ValueKey(playerIndex),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
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
  });

  final int playerCount;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
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
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : AppColors.surfaceBg,
              border: Border.all(
                color:
                    i == currentIndex ? AppColors.primary : AppColors.stroke,
              ),
            ),
            child: Text(
              '玩家 $i',
              style: TextStyle(
                color: i == currentIndex
                    ? AppColors.primary
                    : AppColors.textSecondary,
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
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.emoji_events_outlined,
            color: AppColors.textSecondary,
            size: 30,
          ),
          SizedBox(height: 10),
          Text(
            '还没有验证通过的单词\n输入第一个单词开启 PK 吧',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        children: [
          // 品牌色圆点作为视觉锚点
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              word,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '玩家 $playerIndex',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}
