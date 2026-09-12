import 'package:flutter/material.dart';

import 'package:horyx/games/word_pk/services/word_pk_online_controller.dart';
import 'package:horyx/games/word_pk/widgets/word_pk_board_view.dart';
import 'package:horyx/shared/network/room_client.dart';
import 'package:horyx/shared/network/room_host.dart';
import 'package:horyx/shared/widgets/online_game_page_shell.dart';

/// 单词PK 联机对局页
/// 由房间等待页满员开局后接管房间连接（房主/客户端所有权移入本页）。
/// 页面骨架（控制器生命周期/终局弹窗/退出确认/顶栏框架）见
/// [OnlineGamePageShell]，本页无额外交互状态，只提供对局视图。
/// 提交统一经房主校验，全端随广播同步；
/// 页面销毁即退出对局并关闭连接（联机对局不落本地存档）。
class WordPkOnlinePage extends StatelessWidget {
  const WordPkOnlinePage.host({super.key, required this.host})
      : client = null;

  const WordPkOnlinePage.client({super.key, required this.client})
      : host = null;

  /// 房主连接（房主模式；与本页生命周期绑定，dispose 时关闭即解散房间）
  final RoomHost? host;

  /// 客户端连接（客户端模式；dispose 时关闭即退出房间）
  final RoomClient? client;

  @override
  Widget build(BuildContext context) {
    return OnlineGamePageShell<WordPkOnlineController>(
      title: '单词PK · 联机',
      exitMessage: '退出后将断开与房间的连接，已提交的单词不会保存',
      createController: () => host != null
          ? WordPkOnlineController.host(host!)
          : WordPkOnlineController.client(client!),
      buildGameView: (context, controller, requestExit) => WordPkBoardView(
        playerCount: controller.playerCount,
        currentPlayer: controller.currentPlayer,
        entries: controller.entries,
        onSubmit: controller.submitWord,
        // isMyTurn 已含终局判断：终局后禁输（连接已断，提交无处可去）
        inputEnabled: controller.isMyTurn,
        selfSeat: controller.mySeat,
      ),
    );
  }
}
