import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:horyx/games/chess/models/chess_board.dart';
import 'package:horyx/games/chess/models/chess_piece.dart';
import 'package:horyx/games/chess/services/chess_rules.dart';

/// 规则引擎压力测试：随机对局不变量 + 攻击检测与走子生成的一致性
/// 固定随机种子保证可复现；发现不一致时输出局面编码便于复现排查
void main() {
  /// 攻击/走法一致性（仅对有子的格检查）：
  /// 攻击语义 = 「能吃到 pos 上的子」（与将军检测一致——将军时 pos 是王），
  /// 空格的「平走可达」不等于「可吃」（典型如炮平走可达的空格隔子后不可吃），故不检查。
  /// 等式：isSquareAttacked(pos, C) == ∃C 方棋子（相/仕除外，攻击检测有意不纳入）
  /// 的伪合法走法落点为 pos（pos 上有 C 方己子时双方都必须为 false）
  void checkAttackConsistency(ChessBoard board, String context) {
    for (var row = 0; row < ChessBoard.rows; row++) {
      for (var col = 0; col < ChessBoard.cols; col++) {
        final pos = (col, row);
        final occupant = board.pieceAt(pos);
        if (occupant == null) continue;
        for (final color in ChessColor.values) {
          var expected = false;
          if (occupant.color != color) {
            for (var r2 = 0; r2 < ChessBoard.rows && !expected; r2++) {
              for (var c2 = 0; c2 < ChessBoard.cols && !expected; c2++) {
                final p = board.pieceAt((c2, r2));
                if (p == null || p.color != color) continue;
                // 相/仕活动不出自方半场，攻击检测有意不纳入
                if (p.type == ChessPieceType.bishop ||
                    p.type == ChessPieceType.advisor) {
                  continue;
                }
                if (ChessRules.movesFor(board, (c2, r2)).any((m) => m.to == pos)) {
                  expected = true;
                }
              }
            }
          }
          expect(
            ChessRules.isSquareAttacked(board, pos, color),
            expected,
            reason: '攻击检测与走子生成不一致（$context）：'
                '$pos / $color（占位 ${occupant.color}）/ 局面 ${board.encode()}',
          );
        }
      }
    }
  }

  /// 随机对局：从开局随机走合法着法直到终局或步数上限，
  /// 每步校验编码往返、走子/回退精确性与王存活等不变量
  void playRandomGame(Random rng, int maxMoves, String tag) {
    final board = ChessBoard.initial();
    var turn = ChessColor.red;
    final history = <(ChessMove, ChessPiece?)>[];
    var gameOver = false;

    for (var step = 0; step < maxMoves && !gameOver; step++) {
      // 收集当前行棋方的全部合法着法
      final allMoves = <ChessMove>[];
      for (var row = 0; row < ChessBoard.rows; row++) {
        for (var col = 0; col < ChessBoard.cols; col++) {
          final p = board.pieceAt((col, row));
          if (p != null && p.color == turn) {
            allMoves.addAll(ChessRules.legalMovesFor(board, (col, row)));
          }
        }
      }
      // 对局应已由 judgeEnd 终结：无着法时终止本局
      if (allMoves.isEmpty) {
        expect(ChessRules.judgeEnd(board, turn), isNotNull,
            reason: '无合法着法但 judgeEnd 未判定终局（$tag 第 $step 步）');
        gameOver = true;
        break;
      }
      expect(ChessRules.judgeEnd(board, turn), isNull,
          reason: '有着法但 judgeEnd 误判终局（$tag 第 $step 步）');

      // 随机走一步
      final move = allMoves[rng.nextInt(allMoves.length)];
      final before = board.encode();
      final captured = board.applyMove(move);
      history.add((move, captured));

      // 不变量 1：走后编码可往返还原
      final after = board.encode();
      expect(ChessBoard.decode(after).encode(), after,
          reason: '走后编码往返不一致（$tag 第 $step 步）');

      // 不变量 2：走后不得出现将帅照面（legalMovesFor 应已过滤）
      expect(ChessRules.kingsFacing(board), isFalse,
          reason: '走后出现照面（$tag 第 $step 步）');

      // 不变量 3：王存活（合法着法中不应包含吃王）
      expect(findKingForTest(board, ChessColor.red), isNotNull,
          reason: '红帅消失（$tag 第 $step 步）');
      expect(findKingForTest(board, ChessColor.black), isNotNull,
          reason: '黑将消失（$tag 第 $step 步）');

      // 周期性做攻击/走法一致性全盘检查（开销较大，抽样执行）
      if (step % 15 == 0) {
        checkAttackConsistency(board, '$tag 第 $step 步后');
      }

      // 回退校验：撤销该步后局面必须精确还原
      board.revertMove(move, captured);
      expect(board.encode(), before,
          reason: '回退未精确还原（$tag 第 $step 步）');
      // 重新执行该步继续对局
      board.applyMove(move);

      // 终局判定：对方无路可走则本局结束
      turn = turn == ChessColor.red ? ChessColor.black : ChessColor.red;
      if (ChessRules.judgeEnd(board, turn) != null) {
        gameOver = true;
      }
    }
  }

  test('攻击检测与走子生成在开局局面完全一致', () {
    checkAttackConsistency(ChessBoard.initial(), '开局');
  });

  test('随机对局压力测试（固定种子，20 局 × 最多 300 步）', () {
    final rng = Random(42);
    for (var game = 0; game < 20; game++) {
      playRandomGame(rng, 300, '对局 $game');
    }
  });

  test('不同种子覆盖更多局面形态', () {
    for (var seed = 1; seed <= 5; seed++) {
      playRandomGame(Random(seed), 200, '种子 $seed');
    }
  });
}

/// 测试辅助：查找某方帅/将位置（王存在性断言用，未找到返回 null）
ChessPos? findKingForTest(ChessBoard board, ChessColor color) {
  for (var row = 0; row < ChessBoard.rows; row++) {
    for (var col = 0; col < ChessBoard.cols; col++) {
      final p = board.pieceAt((col, row));
      if (p != null && p.color == color && p.type == ChessPieceType.king) {
        return (col, row);
      }
    }
  }
  return null;
}
