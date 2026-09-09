import 'package:flutter/material.dart';

import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/widgets/chess_board_view.dart';
import 'package:horyx/games/chess/widgets/chess_setup_view.dart';
import 'package:horyx/shared/pages/room_page.dart';
import 'package:horyx/shared/widgets/app_top_bar.dart';

/// 中国象棋游戏页
/// 当前为骨架阶段：设置视图提供对局模式选择（本地/局域网），
/// 对局视图暂为静态棋盘展示（走子交互与终局流程后续接入）
/// 状态栏样式由 MaterialApp 的 builder 统一处理（随主题亮度变化）
class ChessPage extends StatefulWidget {
  const ChessPage({super.key});

  /// 联机房间标识名：GameData 登记、建房入口与房间标识卡共用的
  /// 单一事实来源（注册数据归游戏模块自身，注册中心只做汇总）
  static const String gameName = '中国象棋';

  /// 游戏图标：与 [gameName] 同为注册数据的单一来源
  static const IconData gameIcon = Icons.grid_on_rounded;

  @override
  State<ChessPage> createState() => _ChessPageState();
}

class _ChessPageState extends State<ChessPage> {
  /// 是否已开始对局（false = 对局模式设置阶段）
  bool _started = false;

  /// 对局棋盘（开始对局时初始化为开局局面；走子状态阶段 6 接入）
  ChessBoard? _board;

  /// 开始本地对局：进入对局视图，展示静态开局局面
  void _onStart() {
    setState(() {
      _board = ChessBoard.initial();
      _started = true;
    });
  }

  /// 局域网模式：创建房间并进入等待页（固定 2 人，自己为玩家 1）
  /// 联机对局页尚未接入：满员后停留在等待页「即将开始」过渡态
  void _createRoom() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomPage.host(
          gameName: ChessPage.gameName,
          icon: ChessPage.gameIcon,
          capacity: 2,
        ),
      ),
    );
  }

  /// 回到设置视图（对局视图暂无对局内容，退出无需确认）
  void _backToSetup() {
    setState(() => _started = false);
  }

  /// 退出请求：设置阶段直接退出页面，对局阶段回设置视图
  void _requestExit() {
    if (!_started) {
      Navigator.of(context).pop();
      return;
    }
    _backToSetup();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 对局阶段拦截系统返回（回设置视图），设置阶段允许直接返回
      canPop: !_started,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToSetup();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppTopBar(
                title: '中国象棋',
                showBack: true,
                onBack: _requestExit,
              ),
              Expanded(
                // 阶段切换动画：设置视图 <-> 对局视图
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _started
                      ? _buildGameView()
                      : ChessSetupView(
                          key: const ValueKey('setup'),
                          onStart: _onStart,
                          onCreateRoom: _createRoom,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 对局视图：静态棋盘展示（选子/走子交互在阶段 6 接入）
  Widget _buildGameView() {
    final board = _board;
    if (board == null) {
      // _started 时必有棋盘；空值兜底回设置视图，防御异常路径
      _backToSetup();
      return const SizedBox.shrink();
    }
    return ChessBoardView(
      key: const ValueKey('board'),
      board: board,
    );
  }
}
