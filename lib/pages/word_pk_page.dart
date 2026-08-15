import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_top_bar.dart';

/// 单词PK游戏页
/// 界面骨架先行，玩法逻辑后续迭代实现
class WordPkPage extends StatelessWidget {
  const WordPkPage({super.key});

  @override
  Widget build(BuildContext context) {
    // push 进入的页面不在 AppShell 树内，需自行处理状态栏样式
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: const [
              AppTopBar(title: '单词PK'),
              // 游戏内容区：玩法待开发，暂为空白占位
              Expanded(child: SizedBox.expand()),
            ],
          ),
        ),
      ),
    );
  }
}
