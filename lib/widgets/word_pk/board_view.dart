import 'package:flutter/material.dart';

import '../primary_button.dart';
import '../../theme/app_theme.dart';

/// 单词PK - 对局视图
/// 展示当前输入者、玩家序列、单词输入区与已验证单词列表
/// 当前为静态 UI 阶段：单词列表为演示数据，输入与提交流程后续迭代接入
class WordPkBoardView extends StatefulWidget {
  const WordPkBoardView({super.key, required this.playerCount});

  /// 参与人数（由设置视图传入）
  final int playerCount;

  @override
  State<WordPkBoardView> createState() => _WordPkBoardViewState();
}

class _WordPkBoardViewState extends State<WordPkBoardView> {
  /// 输入框控制器（提交流程后续迭代实现）
  final _inputController = TextEditingController();

  /// 静态演示单词：接入玩法逻辑后由真实输入驱动
  static const List<String> _demoWords = ['apple', 'banana', 'cherry'];

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
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
                const _CurrentPlayerCard(playerIndex: 1),
                const SizedBox(height: 16),
                _PlayerSequence(
                  playerCount: widget.playerCount,
                  currentIndex: 1,
                ),
                const SizedBox(height: 16),
                // 单词输入行：输入框 + 提交按钮
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        // 英文单词输入场景关闭联想与自动纠正
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: '输入英文单词',
                          hintStyle:
                              const TextStyle(color: AppColors.textSecondary),
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
                    // 提交逻辑属下一迭代，先呈禁用态占位
                    const PrimaryButton(
                      label: '提交',
                      icon: Icons.send_rounded,
                      onPressed: null,
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
                                '${_demoWords.length} 个',
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
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: _demoWords.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) => _WordChip(
                              word: _demoWords[index],
                              playerIndex: index + 1,
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
              Text(
                '玩家 $playerIndex',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
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
  const _PlayerSequence({required this.playerCount, required this.currentIndex});

  final int playerCount;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int i = 1; i <= playerCount; i++)
          Container(
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
