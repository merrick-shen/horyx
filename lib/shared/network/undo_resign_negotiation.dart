import 'package:flutter/foundation.dart';

import 'package:horyx/shared/network/net_message.dart';
import 'package:horyx/shared/network/online_game_controller.dart';

/// 悔棋协商状态机（棋类通用，唯一定义；协议消息见 net_message.dart）
/// idle -> awaitingPeer（我发起了请求，等对方应答）
/// idle -> peerRequesting（对方请求悔棋，等我应答）
/// 应答后回到 idle（同意时随广播回退棋盘）
enum UndoState {
  /// 无进行中的悔棋协商
  idle,

  /// 我方已发起请求，等待对方应答
  awaitingPeer,

  /// 对方发起请求，等待我方应答
  peerRequesting,
}

/// 棋类联机控制器的悔棋/认输协商能力混入（gomoku / chess 共用）。
///
/// undo/resign 协议消息为棋类通用（见 net_message.dart 注释），状态机层
/// 随之统一：悔棋协商全流程（发起/应答/房主仲裁）与认输全流程在此唯一定义
/// ——未来调整协商规则（限时/限次/超时复位）只改这一处，不会双侧静默分叉。
/// 混入方（[OnlineGameControllerBase] 子类）只保留棋局专属钩子：快照回退
/// 实现（五子棋 removeRange / 象棋重放重建）、执子归属校验、认输终局建模
/// 与文案措辞。
///
/// 消息调度约定：混入方在自己的 onHostGameMessage / onClientGameMessage
/// switch 中把 undo/resign 消息分支委托给 [handleHostUndoResignMessage] /
/// [handleClientUndoMessage]；2 人局「对方离开即终局」的 [onSeatLeft]
/// 语义同样在此统一实现（棋类 2 人局行为完全一致）。
mixin UndoResignNegotiationMixin on OnlineGameControllerBase {
  // ============ 混入方需提供的棋局专属钩子 ============

  /// 胜方座位号；null 表示对局进行中或异常终止
  /// （协商/认输入口守卫与对方离开终局守卫共用）
  @protected
  int? get winnerSeat;

  /// 已生效手数（悔棋快照基准）
  @protected
  int get moveCount;

  /// 是否轮到己方行动（悔棋发起时机守卫：只能悔自己的上一手）
  @protected
  bool get isMyTurn;

  /// 第 [moveIndex] 手（0 基）是否为 [seat] 方所下
  /// （房主仲裁校验：快照末手须为请求方所下，防"悔对方的子"或篡改）
  @protected
  bool isMoveBy(int moveIndex, int seat);

  /// 悔棋回退到快照手数 [target]（含协商期间的新增手数）：
  /// 五子棋 removeRange、象棋从初始局面重放重建，各自实现
  @protected
  void applyUndoRollback(int target);

  /// 认输生效：[winner] 获胜，认输终局按各棋局建模
  /// （五子棋 wonByResign 标记 / 象棋 ChessEndReason.resign）
  @protected
  void declareResignWinner(int winner);

  /// 尚无手数可悔的提示文案（落子/走子措辞按棋局区分）
  @protected
  String get noMoveHintText;

  // ============ 协商状态 ============

  /// 悔棋协商状态（页面据此切换悔棋按钮文案与可点状态）
  UndoState undoState = UndoState.idle;

  /// 同意悔棋后的目标手数（发起方"悔自己上一手"后的长度）
  /// 发起时快照：协商期间对方若又走子，同意后一并回退到快照（B9）
  int _undoTarget = 0;

  /// 对局是否已分胜负或异常终局（协商/认输入口守卫）
  bool get _isGameOver => winnerSeat != null || gameEndedText != null;

  /// 发起悔棋请求（悔自己上一手）：仅对方回合可发起——轮到自己时
  /// 最后一手是对方的子，悔棋语义不成立（B9）。发起时快照手数，
  /// 同意后回退到快照（协商期间对方新走的子一并回退）。
  /// 房主直接进入协商（本地应答方是客户端），客户端发请求给房主
  void requestUndo() {
    if (_isGameOver) return;
    if (moveCount == 0) {
      onHint?.call(noMoveHintText);
      return;
    }
    if (isMyTurn) {
      // 最后一手是对方的子，悔棋只能悔自己的上一手
      onHint?.call('只能在对方回合悔棋（悔自己的上一手）');
      return;
    }
    if (undoState != UndoState.idle) return; // 已有协商进行中
    _undoTarget = moveCount - 1;
    final msg = _msg(NetMessageType.undoRequest, {'count': moveCount});
    final host = this.host;
    if (host != null) {
      undoState = UndoState.awaitingPeer;
      notifyListeners();
      host.sendTo(peerSeat, msg);
    } else {
      // 客户端同样置 awaitingPeer：按钮进入"等待对方应答"防重复发起
      undoState = UndoState.awaitingPeer;
      notifyListeners();
      client?.send(msg);
    }
  }

  /// 应答对方的悔棋请求（仅 peerRequesting 状态有效）
  /// 同意：房主直接回退并广播；客户端发应答给房主仲裁
  void respondUndo(bool accept) {
    if (undoState != UndoState.peerRequesting) return;
    final host = this.host;
    if (host != null) {
      undoState = UndoState.idle;
      if (accept) {
        applyUndoRollback(_undoTarget);
        notifyListeners();
        host.broadcast(
          _msg(NetMessageType.undoApplied, {'target': _undoTarget}),
        );
      } else {
        notifyListeners();
        host.sendTo(
          peerSeat,
          _msg(NetMessageType.undoResponse, {'accept': false}),
        );
      }
    } else {
      undoState = UndoState.idle;
      notifyListeners();
      client?.send(
        _msg(NetMessageType.undoResponse, {'accept': accept}),
      );
    }
  }

  /// 认输：判对方获胜（房主本地生效并广播，客户端声明给房主）
  void resign() {
    if (_isGameOver) return;
    final host = this.host;
    if (host != null) {
      // 对方获胜：peerSeat 与 _onHostResign 的 peerSeatOf(seat) 同一规则
      declareResignWinner(peerSeat);
      notifyListeners();
      host.broadcast(
        NetMessage(
          type: NetMessageType.gameOver,
          payload: {'reason': 'resign', 'winner': peerSeat},
        ),
      );
    } else {
      client?.send(_msg(NetMessageType.resign));
    }
  }

  /// 房主侧：客户端悔棋/认输消息统一处理
  /// （undoRequest/undoResponse/resign，由混入方 onHostGameMessage 分支调度）
  @protected
  void handleHostUndoResignMessage(int seat, NetMessage msg) {
    switch (msg.type) {
      case NetMessageType.undoRequest:
        _onHostUndoRequest(seat, msg);
      case NetMessageType.undoResponse:
        _onHostUndoResponse(seat, msg);
      case NetMessageType.resign:
        _onHostResign(seat);
      default:
        break;
    }
  }

  /// 房主收悔棋请求（仅来自客户端）：本地进入待应答状态（页面弹窗），
  /// 不转发——房主自己就是应答方，本地 respondUndo 处理。
  /// 终极校验载荷 count（发起方快照手数）：数值合法且快照末手确实是
  /// 请求方所下（防"悔对方的子"或篡改），否则忽略请求
  void _onHostUndoRequest(int seat, NetMessage msg) {
    if (_isGameOver) return;
    if (undoState != UndoState.idle) return; // 已有协商进行中
    final count = msg.payload['count'];
    if (count is! int || count < 1 || count > moveCount) return;
    if (!isMoveBy(count - 1, seat)) return;
    _undoTarget = count - 1;
    undoState = UndoState.peerRequesting;
    notifyListeners();
  }

  /// 房主收悔棋应答（客户端应答房主发起的请求）：
  /// 同意则广播回退（双端各自执行），拒绝仅本地提示；状态复位
  void _onHostUndoResponse(int seat, NetMessage msg) {
    if (undoState != UndoState.awaitingPeer) return; // 非我方请求的应答，忽略
    undoState = UndoState.idle;
    final accepted = msg.payload['accept'] == true;
    if (accepted) {
      applyUndoRollback(_undoTarget);
      notifyListeners();
      host?.broadcast(
        _msg(NetMessageType.undoApplied, {'target': _undoTarget}),
      );
    } else {
      onHint?.call('对方拒绝了悔棋请求');
      notifyListeners();
    }
  }

  /// 房主收认输声明：判对方获胜并广播终局
  void _onHostResign(int seat) {
    if (_isGameOver) return;
    declareResignWinner(peerSeatOf(seat));
    notifyListeners();
    host?.broadcast(
      NetMessage(
        type: NetMessageType.gameOver,
        payload: {'reason': 'resign', 'winner': peerSeatOf(seat)},
      ),
    );
  }

  /// 客户端侧：房主悔棋消息统一处理
  /// （undoRequest/undoResponse/undoApplied，由混入方 onClientGameMessage
  /// 分支调度）
  @protected
  void handleClientUndoMessage(NetMessage msg) {
    switch (msg.type) {
      case NetMessageType.undoRequest:
        // 房主转发的悔棋请求：进入待应答状态（页面弹窗）
        undoState = UndoState.peerRequesting;
        notifyListeners();
      case NetMessageType.undoResponse:
        // 我方请求的应答：状态复位；同意/拒绝都不动棋盘，
        // 同意的回退统一以 undoApplied 广播为准（避免与应答双回退）
        undoState = UndoState.idle;
        if (msg.payload['accept'] != true) {
          onHint?.call('对方拒绝了悔棋请求');
        }
        notifyListeners();
      case NetMessageType.undoApplied:
        // 广播回退（target = 发起方快照）：双端同步回退到快照
        // （含协商期间的新增手数）。请求方（awaitingPeer，房主本地
        // 同意不经过应答消息）在此一并复位协商状态
        undoState = UndoState.idle;
        final target = msg.payload['target'];
        if (target is int && target >= 0 && target < moveCount) {
          applyUndoRollback(target);
        } else if (moveCount > 0) {
          // target 缺失/非法的兜底：退一手（同版本协议下不会走到）
          applyUndoRollback(moveCount - 1);
        }
        notifyListeners();
      default:
        break;
    }
  }

  /// 房主侧：对方离开（掉线/主动退出）——2 人局对局直接结束，不判胜负
  /// （与单词PK一致：中途退出属异常终止，留局方无胜利可言；
  /// 2 人局无人可收到广播，仅本地终局）
  @override
  void onSeatLeft(int seat) {
    if (gameEndedText != null || winnerSeat != null) return;
    endGame(EndGameReason.peerLeft);
    notifyListeners();
  }
}

/// 构造对局消息的便捷方法（悔棋协商/认输等）
NetMessage _msg(
  NetMessageType type, [
  Map<String, dynamic> payload = const {},
]) =>
    NetMessage(type: type, payload: payload);
