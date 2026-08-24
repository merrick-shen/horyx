import 'package:flutter/material.dart';

import '../../data/game_data.dart';
import '../../models/games/word_entry.dart';
import '../../models/games/word_pk_game_state.dart';
import '../../services/storage/word_pk_storage.dart';
import '../../services/word_pk/word_validator.dart';
import '../../utils/hint_bar.dart';
import '../../widgets/common/app_top_bar.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/word_pk/board_view.dart';
import '../../widgets/word_pk/setup_view.dart';
import '../lan/room_page.dart';
import 'word_pk_online_page.dart';

/// 单词PK游戏页
/// 持有对局状态（人数、当前输入者、单词列表），统一负责：
/// 提交校验、退出确认弹窗、对局存档与恢复
/// 状态栏样式由 MaterialApp 的 builder 统一处理（随主题亮度变化）
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
    final state = await WordPkStorage.instance.load();
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

  /// 局域网模式：创建房间并进入等待页（自己为玩家 1，房主）
  /// 满员后等待页自动跳转联机对局页（连接所有权随之移交）
  void _createRoom(int count) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomPage.host(
          gameName: GameData.wordPk.name,
          capacity: count,
          hostGameBuilder: (context, host) =>
              WordPkOnlinePage.host(host: host),
        ),
      ),
    );
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

  /// 退出请求：对局中弹出三选项确认弹窗（保存退出/不保存退出/取消）
  /// 对局中尚无提交记录时无进行中内容，直接返回设置视图（与计分器未计分退出一致）
  /// 设置阶段直接退出页面
  Future<void> _requestExit() async {
    if (!_started) {
      // 设置阶段顶栏返回：清理残留提示（棋盘阶段被退回设置后可能遗留）
      exitPageClean(context);
      return;
    }
    // 开局后还没提交任何单词：不打扰，直接回设置
    if (_entries.isEmpty) {
      // 非法提交的提示仍挂在 messenger 上，回设置视图前清理
      clearHint(context);
      setState(() => _started = false);
      return;
    }
    final result = await showConfirmDialog(
      context,
      title: '退出对局？',
      message: '保存并退出后，下次进入可从当前进度继续对战',
      confirmLabel: '保存并退出',
      neutralLabel: '不保存并退出',
    );
    if (!mounted) return;

    switch (result) {
      case ConfirmResult.confirm:
        // 持久化完整对局状态后退出
        await WordPkStorage.instance.save(
          WordPkGameState(
            playerCount: _playerCount,
            currentPlayer: _currentPlayer,
            entries: List.of(_entries),
            savedAt: DateTime.now(),
          ),
        );
        if (mounted) exitPageClean(context);
      case ConfirmResult.neutral:
        // 放弃当前对局：清除旧存档，避免下次误提示可继续
        await WordPkStorage.instance.clear();
        if (mounted) exitPageClean(context);
      case ConfirmResult.cancel:
        // 留在对局
        break;
    }
  }

  /// 提交校验：格式 → 重复 → 真实性；通过则入列并轮换，返回是否通过
  bool _submitWord(String raw) {
    raw = raw.trim();
    if (raw.isEmpty) {
      showPersistentHint(context, '请输入英文单词');
      return false;
    }
    // 仅允许纯英文字母，提前拦截中文、数字、空格等输入
    if (!RegExp(r'^[A-Za-z]+$').hasMatch(raw)) {
      showPersistentHint(context, '单词只能由英文字母组成');
      return false;
    }
    // 统一小写后参与重复比较，忽略大小写差异
    final word = raw.toLowerCase();
    if (_entries.any((e) => e.word == word)) {
      showPersistentHint(context, '单词已重复');
      return false;
    }
    if (!WordValidator.isValid(word)) {
      showPersistentHint(context, '不是有效的英文单词');
      return false;
    }

    // 全部校验通过：插入列表头部（最新置顶）并轮换至下一位输入者
    setState(() {
      _entries.insert(0, WordEntry(word: word, playerIndex: _currentPlayer));
      _currentPlayer = _currentPlayer % _playerCount + 1;
    });
    // 新输入成功时清除遗留的错误提示，避免信息干扰
    hideHint(context);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 对局中拦截系统返回（走保存确认弹窗），设置阶段允许直接返回
      canPop: !_started,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          // 系统返回直接弹出（设置阶段 canPop）：绕过 _requestExit，需在此清理
          clearHint(context);
          return;
        }
        _requestExit();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppTopBar(
                title: '单词PK',
                showBack: true,
                onBack: _requestExit,
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
                          onCreateRoom: _createRoom,
                          savedState: _savedState,
                          onResume: _resumeSaved,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
