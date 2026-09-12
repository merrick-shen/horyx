import 'package:flutter/material.dart';

import 'package:horyx/games/word_pk/models/word_pk_entry.dart';
import 'package:horyx/games/word_pk/models/word_pk_game_state.dart';
import 'package:horyx/games/word_pk/services/word_pk_storage.dart';
import 'package:horyx/games/word_pk/services/word_pk_validator.dart';
import 'package:horyx/shared/storage/archive_storage.dart';
import 'package:horyx/shared/storage/game_archive_state.dart';
import 'package:horyx/shared/utils/hint_bar.dart';
import 'package:horyx/shared/widgets/alert_dialog.dart';
import 'package:horyx/shared/widgets/app_top_bar.dart';
import 'package:horyx/shared/widgets/confirm_dialog.dart';
import 'package:horyx/games/word_pk/widgets/word_pk_board_view.dart';
import 'package:horyx/games/word_pk/widgets/word_pk_setup_view.dart';
import 'package:horyx/shared/pages/room_page.dart';
import 'package:horyx/games/word_pk/pages/word_pk_online_page.dart';

/// 单词PK游戏页
/// 持有对局状态（人数、当前输入者、单词列表），统一负责：
/// 提交校验、退出确认弹窗、对局存档与恢复
/// 状态栏样式由 MaterialApp 的 builder 统一处理（随主题亮度变化）
class WordPkPage extends StatefulWidget {
  const WordPkPage({super.key});

  /// 联机房间标识名：GameData 登记、建房入口与房间标识卡共用的
  /// 单一事实来源（注册数据归游戏模块自身，注册中心只做汇总）
  static const String gameName = '单词PK';

  /// 游戏图标：与 [gameName] 同为注册数据的单一来源
  static const IconData gameIcon = Icons.spellcheck_rounded;

  @override
  State<WordPkPage> createState() => _WordPkPageState();
}

class _WordPkPageState
    extends GameArchiveStateBase<WordPkPage, WordPkGameState> {
  /// 是否已开始对局（false = 人数设置阶段）
  bool _started = false;

  /// 本局人数
  int _playerCount = WordPkSetupView.minPlayers;

  /// 当前输入者序号（从 1 开始）
  int _currentPlayer = 1;

  /// 已验证通过的单词列表（最新置顶）
  final List<WordPkEntry> _entries = [];

  @override
  ArchiveStorage<WordPkGameState> get archiveStorage =>
      WordPkStorage.instance;

  @override
  bool get isInSetupPhase => !_started;

  @override
  void initState() {
    super.initState();
    loadSavedState();
  }

  void _onStart(int count) {
    setState(() {
      _playerCount = count;
      _currentPlayer = 1;
      _entries.clear();
      _started = true;
      // 开启新对局后不再展示旧存档入口
      savedState = null;
    });
  }

  /// 局域网模式：创建房间并进入等待页（自己为玩家 1，房主）
  /// 满员后等待页自动跳转联机对局页（连接所有权随之移交）
  void _createRoom(int count) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomPage.host(
          gameName: WordPkPage.gameName,
          icon: WordPkPage.gameIcon,
          capacity: count,
          hostGameBuilder: (context, host) =>
              WordPkOnlinePage.host(host: host),
        ),
      ),
    );
  }

  /// 恢复未完成对局：从存档还原人数、回合进度与单词列表
  void _resumeSaved() {
    final saved = savedState;
    if (saved == null) return;
    setState(() {
      _playerCount = saved.playerCount;
      _currentPlayer = saved.currentPlayer;
      _entries
        ..clear()
        ..addAll(saved.entries);
      _started = true;
      savedState = null;
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
      // 重新加载存档刷新恢复入口——开局时入口已被置空（savedState = null），
      // 未提交即退出时磁盘上的旧存档仍在，回设置后应重新展示
      loadSavedState();
      return;
    }
    await confirmExitWithArchive(
      this,
      // 持久化完整对局状态后退出
      onSave: () => WordPkStorage.instance.save(
        WordPkGameState(
          playerCount: _playerCount,
          currentPlayer: _currentPlayer,
          entries: List.of(_entries),
          savedAt: DateTime.now(),
        ),
      ),
      onDiscard: WordPkStorage.instance.clear,
      onExit: () => exitPageClean(context),
    );
  }

  /// 提交校验（规则唯一来源 WordPkValidator.validateWord）：
  /// 通过则入列并轮换，返回是否通过
  bool _submitWord(String raw) {
    final error = WordPkValidator.validateWord(raw, _entries);
    if (error != null) {
      showAlertDialog(context, message: error);
      return false;
    }

    // 全部校验通过：统一小写后插入列表头部（最新置顶）并轮换至下一位输入者
    final word = raw.trim().toLowerCase();
    setState(() {
      _entries.insert(0, WordPkEntry(word: word, playerIndex: _currentPlayer));
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
                          savedState: savedState,
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
