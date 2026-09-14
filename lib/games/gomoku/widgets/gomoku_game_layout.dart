import 'package:flutter/material.dart';

import 'package:horyx/shared/widgets/confirm_move_row.dart';
import 'package:horyx/shared/widgets/page_content.dart';
import 'package:horyx/shared/widgets/stone_board.dart';
import 'package:horyx/shared/widgets/stone_turn_card.dart';

/// 五子棋对局布局（本地与联机对局视图共用）：
/// 执子提示卡 + 棋盘 + 落子确认行 + 底部按钮插槽。
/// 两视图仅执子卡副标题（本地"当前执子"/联机"轮到你落子"等）与
/// 底部按钮集不同，以 [turnSubtitle] 参数与 [actions] 插槽注入；
/// 落子序列转显式颜色棋子集合的映射在此单点维护
class GomokuGameLayout extends StatelessWidget {
  const GomokuGameLayout({
    super.key,
    required this.boardSize,
    required this.moves,
    required this.pending,
    required this.winner,
    required this.turnSubtitle,
    required this.onCellTap,
    required this.onCancelMove,
    required this.onConfirmMove,
    required this.actions,
  });

  /// 棋盘路数
  final int boardSize;

  /// 已确认落子序列
  final List<(int, int)> moves;

  /// 预选落子位置；null 表示无预选
  final (int, int)? pending;

  /// 胜方文案；null 表示对局进行中（执子卡切换胜方展示，终局后无预选）
  final String? winner;

  /// 执子卡副标题（本地"当前执子"/联机"轮到你落子"等，由页面按语义传入）
  final String turnSubtitle;

  /// 点击棋盘交叉点回调
  final void Function(int col, int row) onCellTap;

  /// 点击「取消」回调：清除落子预选
  final VoidCallback onCancelMove;

  /// 点击「下棋」回调：确认落子
  final VoidCallback onConfirmMove;

  /// 底部按钮插槽：本地为悔棋/再来一局，联机为退出/悔棋/认输操作按钮组
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    // 落子确认按钮仅在棋盘上有预选棋子时出现（终局后无预选）
    final hasPending = pending != null;
    final blackTurn = moves.length.isEven;

    return SizedBox.expand(
      child: PageContent(
        // 对局页收窄页边距：棋盘卡片自带边框，把宽度尽量让给棋盘
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 对局中提示执子方（图标颜色对应棋子）；终局提示胜方
            StoneTurnCard(
              isOver: winner != null,
              blackToMove: blackTurn,
              winner: winner,
              subtitle: turnSubtitle,
            ),
            const SizedBox(height: 16),
            // 棋盘占据剩余空间，正方形自适应宽高较小者
            Expanded(
              child: Center(
                // 五子棋无提子，落子序列奇偶即可推导颜色（先手黑）
                // 转换为显式颜色棋子集合供通用棋盘组件绘制
                child: StoneBoard(
                  size: boardSize,
                  stones: [
                    for (int i = 0; i < moves.length; i++)
                      (moves[i].$1, moves[i].$2, i.isEven),
                  ],
                  pending: pending == null
                      ? null
                      : (pending!.$1, pending!.$2, moves.length.isEven),
                  onCellTap: onCellTap,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ConfirmMoveRow(
              visible: hasPending,
              onCancelMove: onCancelMove,
              onConfirmMove: onConfirmMove,
            ),
            const SizedBox(height: 12),
            actions,
          ],
        ),
      ),
    );
  }
}
