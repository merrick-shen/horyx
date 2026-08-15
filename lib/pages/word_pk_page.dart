import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_top_bar.dart';
import '../widgets/word_pk/board_view.dart';
import '../widgets/word_pk/setup_view.dart';

/// 单词PK游戏页
/// 阶段流转：人数设置 → 对局（当前为静态 UI 阶段，玩法逻辑后续迭代）
class WordPkPage extends StatefulWidget {
  const WordPkPage({super.key});

  @override
  State<WordPkPage> createState() => _WordPkPageState();
}

class _WordPkPageState extends State<WordPkPage> {
  /// 是否已开始对局（false = 人数设置阶段）
  bool _started = false;

  /// 本局人数（由设置视图传入，对局视图使用）
  int _playerCount = WordPkSetupView.minPlayers;

  void _onStart(int count) {
    setState(() {
      _playerCount = count;
      _started = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // push 进入的页面不在 AppShell 树内，需自行处理状态栏样式
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const AppTopBar(title: '单词PK'),
              Expanded(
                // 阶段切换动画：设置视图 <-> 对局视图淡入淡出
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _started
                      ? WordPkBoardView(
                          key: const ValueKey('board'),
                          playerCount: _playerCount,
                        )
                      : WordPkSetupView(
                          key: const ValueKey('setup'),
                          onStart: _onStart,
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
