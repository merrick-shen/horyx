import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/word_entry.dart';
import '../models/word_pk_game_state.dart';
import '../services/word_pk_storage.dart';
import '../services/word_validator.dart';
import '../theme/app_theme.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/word_pk/board_view.dart';
import '../widgets/word_pk/setup_view.dart';

/// 单词PK游戏页
/// 持有对局状态（人数、当前输入者、单词列表），统一负责：
/// 提交校验、退出确认弹窗、对局存档与恢复
class WordPkPage extends StatefulWidget {
  const WordPkPage({super.key});

  @override
  State<WordPkPage> createState() => _WordPkPageState();
}

class _WordPkPageState extends State<WordPkPage> {
  /// 是否已开始对局（false = 人数设置阶段）
  bool _started = false;

  /// 本局人数
  int _playerCount = WordPkSetupView.minPlayers;

  /// 当前输入者序号（从 1 开始）
  int _currentPlayer = 1;

  /// 已验证通过的单词列表（最新置顶）
  final List<WordEntry> _entries = [];

  /// 进入时检测到的未完成存档；恢复或开始新对局后清空展示
  WordPkGameState? _savedState;

  @override
  void initState() {
    super.initState();
    _loadSavedState();
  }

  /// 启动时检测未完成对局，存在则在设置视图展示恢复入口
  Future<void> _loadSavedState() async {
    final state = await WordPkStorage.load();
    if (state != null && mounted) {
      setState(() => _savedState = state);
    }
  }

  void _onStart(int count) {
    setState(() {
      _playerCount = count;
      _currentPlayer = 1;
      _entries.clear();
      _started = true;
      // 开启新对局后不再展示旧存档入口
      _savedState = null;
    });
  }

  /// 恢复未完成对局：从存档还原人数、回合进度与单词列表
  void _resumeSaved() {
    final saved = _savedState;
    if (saved == null) return;
    setState(() {
      _playerCount = saved.playerCount;
      _currentPlayer = saved.currentPlayer;
      _entries
        ..clear()
        ..addAll(saved.entries);
      _started = true;
      _savedState = null;
    });
  }

  /// 退出请求：确认后保存并退出（设置阶段直接返回）
  Future<void> _requestExit() async {
    if (!_started) {
      Navigator.of(context).pop();
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: '退出对局？',
      message: '保存并退出后，下次进入可从当前进度继续对战',
      confirmLabel: '保存并退出',
    );
    if (!confirmed || !mounted) return;

    // 持久化完整对局状态后退出
    await WordPkStorage.save(
      WordPkGameState(
        playerCount: _playerCount,
        currentPlayer: _currentPlayer,
        entries: List.of(_entries),
        savedAt: DateTime.now(),
      ),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// 提交校验：格式 → 重复 → 真实性；通过则入列并轮换，返回是否通过
  bool _submitWord(String raw) {
    raw = raw.trim();
    if (raw.isEmpty) {
      _showHint('请输入英文单词');
      return false;
    }
    // 仅允许纯英文字母，提前拦截中文、数字、空格等输入
    if (!RegExp(r'^[A-Za-z]+$').hasMatch(raw)) {
      _showHint('单词只能由英文字母组成');
      return false;
    }
    // 统一小写后参与重复比较，忽略大小写差异
    final word = raw.toLowerCase();
    if (_entries.any((e) => e.word == word)) {
      _showHint('单词已重复');
      return false;
    }
    if (!WordValidator.isValid(word)) {
      _showHint('不是有效的英文单词');
      return false;
    }

    // 全部校验通过：插入列表头部（最新置顶）并轮换至下一位输入者
    setState(() {
      _entries.insert(0, WordEntry(word: word, playerIndex: _currentPlayer));
      _currentPlayer = _currentPlayer % _playerCount + 1;
    });
    // 新输入成功时清除遗留的错误提示，避免信息干扰
    _hideHint();
    return true;
  }

  /// 展示错误/引导提示
  /// 错误提示不自动消失（需手动关闭），避免玩家漏看
  void _showHint(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(days: 1),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(label: '知道了', onPressed: _hideHint),
        ),
      );
  }

  void _hideHint() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  @override
  Widget build(BuildContext context) {
    // push 进入的页面不在 AppShell 树内，需自行处理状态栏样式
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        // 对局中拦截系统返回（走保存确认弹窗），设置阶段允许直接返回
        canPop: !_started,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _requestExit();
        },
        child: Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                AppTopBar(
                  title: '单词PK',
                  leading: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: AppColors.textPrimary,
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
                        ? WordPkBoardView(
                            key: const ValueKey('board'),
                            playerCount: _playerCount,
                            currentPlayer: _currentPlayer,
                            entries: _entries,
                            onSubmit: _submitWord,
                          )
                        : WordPkSetupView(
                            key: const ValueKey('setup'),
                            onStart: _onStart,
                            savedState: _savedState,
                            onResume: _resumeSaved,
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
