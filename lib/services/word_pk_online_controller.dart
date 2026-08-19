import 'package:flutter/foundation.dart';

import '../models/net_message.dart';
import '../models/word_entry.dart';
import 'network/room_client.dart';
import 'network/room_host.dart';
import 'word_validator.dart';

/// 单词PK 联机对局控制器（房主权威模型）
/// 房主端：接收并校验各端提交，生效单词与回合轮换由房主计算后广播；
/// 客户端端：提交单词交房主校验，按广播同步对局状态，不自行推导回合。
/// 全端状态由 wordApplied/turnChanged 驱动，杜绝双端状态分叉。
/// 页面销毁（dispose）即退出对局：控制器负责关闭底层房间连接。
class WordPkOnlineController extends ChangeNotifier {
  /// 以房主身份接管房间（满员开局后由等待页调用）
  WordPkOnlineController.host(RoomHost host)
      : _host = host,
        _client = null,
        mySeat = 1 {
    playerCount = host.capacity;
    _activeSeats = {...host.seats};
    host.onGameMessage = _onHostGameMessage;
    host.onSeatLeft = _onSeatLeft;
  }

  /// 以客户端身份接管房间（收到 gameStart 后由等待页调用）
  WordPkOnlineController.client(RoomClient client)
      : _host = null,
        _client = client,
        mySeat = client.mySeat ?? 1 {
    playerCount = client.capacity;
    _activeSeats = {...client.seats};
    // 挂接对局消息处理（含暂存消息回放），并跟踪连接状态变化
    client.attachGameHandler(_onClientGameMessage);
    client.addListener(_onClientChanged);
  }

  final RoomHost? _host;
  final RoomClient? _client;

  /// 我的座位号（房主固定 1 号位）
  final int mySeat;

  /// 本局总人数
  late final int playerCount;

  /// 仍在对局中的座位集合（中途退出即移除，回合轮换跳过空位）
  late final Set<int> _activeSeats;

  /// 当前输入者座位号（房主权威，客户端随广播更新）
  int currentPlayer = 1;

  /// 已生效单词（最新置顶，与本地对局展示一致）
  final List<WordEntry> entries = [];

  /// 校验拒绝等提示回调（页面接 SnackBar 展示；拒绝理由来自房主）
  void Function(String message)? onHint;

  /// 对局中断说明（断线/房主解散/其他玩家全部离开）；
  /// 非 null 时页面弹窗告知并结束，之后不再恢复
  String? gameEndedText;

  /// 是否轮到自己输入
  bool get isMyTurn => currentPlayer == mySeat;

  /// 提交单词（页面输入框调用；返回 true 表示输入合法、可清空输入框）
  /// 客户端的词法校验在本地完成（省一次往返），真实性仍由房主裁决
  bool submitWord(String raw) {
    final word = raw.trim().toLowerCase();
    if (word.isEmpty) {
      onHint?.call('请输入英文单词');
      return false;
    }
    if (!RegExp(r'^[A-Za-z]+$').hasMatch(word)) {
      onHint?.call('单词只能由英文字母组成');
      return false;
    }
    return _host != null ? _submitAsHost(word) : _submitAsClient(word);
  }

  /// 房主提交：本地完成全部校验（重复/词表），通过即生效并广播
  bool _submitAsHost(String word) {
    if (!isMyTurn) {
      onHint?.call('还没轮到你');
      return false;
    }
    if (entries.any((e) => e.word == word)) {
      onHint?.call('单词已重复');
      return false;
    }
    if (!WordValidator.isValid(word)) {
      onHint?.call('「$word」不是有效的英文单词');
      return false;
    }
    _applyWord(word, mySeat);
    return true;
  }

  /// 客户端提交：发往房主校验，结果异步返回
  /// （通过走 wordApplied 广播同步，拒绝走 wordResult 提示）
  bool _submitAsClient(String word) {
    if (!isMyTurn) {
      onHint?.call('还没轮到你');
      return false;
    }
    _client?.send(
      NetMessage(
        type: NetMessageType.wordSubmit,
        payload: {'word': word},
      ),
    );
    return true;
  }

  /// 房主收到客户端提交：逐项校验，拒绝单独回执提交者，通过则广播生效
  /// （客户端不可信：格式与重复校验在房主侧全部重做一遍）
  void _onHostGameMessage(int seat, NetMessage message) {
    if (message.type != NetMessageType.wordSubmit) return;
    final raw = message.payload['word'];
    if (raw is! String) return;
    final word = raw.trim().toLowerCase();

    if (seat != currentPlayer) {
      _host?.sendTo(seat, _resultMessage(false, 'notYourTurn'));
      return;
    }
    if (word.isEmpty || !RegExp(r'^[A-Za-z]+$').hasMatch(word)) {
      _host?.sendTo(seat, _resultMessage(false, 'format'));
      return;
    }
    if (entries.any((e) => e.word == word)) {
      _host?.sendTo(seat, _resultMessage(false, 'duplicate'));
      return;
    }
    if (!WordValidator.isValid(word)) {
      _host?.sendTo(seat, _resultMessage(false, 'invalid'));
      return;
    }
    _host?.sendTo(seat, _resultMessage(true, null));
    _applyWord(word, seat);
  }

  /// 单词生效：入列 + 轮换到下一在线座位；房主侧同步广播
  void _applyWord(String word, int seat) {
    entries.insert(0, WordEntry(word: word, playerIndex: seat));
    currentPlayer = _nextActiveSeat(currentPlayer);
    notifyListeners();
    _host?.broadcast(
      NetMessage(
        type: NetMessageType.wordApplied,
        payload: {
          'word': word,
          'player': seat,
          'nextPlayer': currentPlayer,
        },
      ),
    );
  }

  /// 环形寻找下一个在线座位（1..N 循环）；全部离线时返回原座位
  int _nextActiveSeat(int from) {
    for (var step = 1; step <= playerCount; step++) {
      final seat = (from - 1 + step) % playerCount + 1;
      if (_activeSeats.contains(seat)) return seat;
    }
    return from;
  }

  /// 房主侧：玩家中途离开（掉线/主动退出）
  void _onSeatLeft(int seat) {
    _activeSeats.remove(seat);
    // 轮到的人离开：直接轮换到下一在线座位并广播（否则对局会卡住等待）
    if (seat == currentPlayer) {
      currentPlayer = _nextActiveSeat(currentPlayer);
      _host?.broadcast(
        NetMessage(
          type: NetMessageType.turnChanged,
          payload: {'player': currentPlayer},
        ),
      );
      notifyListeners();
    }
    // 除自己外全员离开：对局无法继续
    if (_activeSeats.length <= 1 && gameEndedText == null) {
      gameEndedText = '其他玩家均已离开，对局结束';
      notifyListeners();
    }
  }

  /// 客户端侧：处理房主对局消息，全端状态以广播为准
  void _onClientGameMessage(NetMessage message) {
    switch (message.type) {
      case NetMessageType.wordApplied:
        entries.insert(
          0,
          WordEntry(
            word: (message.payload['word'] as String?) ?? '',
            playerIndex: (message.payload['player'] as int?) ?? 0,
          ),
        );
        currentPlayer =
            (message.payload['nextPlayer'] as int?) ?? currentPlayer;
        notifyListeners();
      case NetMessageType.wordResult:
        // 拒绝才提示；通过无需处理（生效以 wordApplied 广播为准）
        if (message.payload['ok'] != true) {
          onHint?.call(_reasonText(message.payload['reason']));
        }
      case NetMessageType.turnChanged:
        currentPlayer = (message.payload['player'] as int?) ?? currentPlayer;
        notifyListeners();
      default:
        break;
    }
  }

  /// 客户端侧：连接状态变化（断线/房主解散 -> 对局终止）
  void _onClientChanged() {
    if (_client?.phase == RoomClientPhase.disconnected &&
        gameEndedText == null) {
      gameEndedText = _client!.disconnectText;
      notifyListeners();
    }
  }

  /// 房主拒绝原因 -> 用户可读文案
  String _reasonText(Object? reason) {
    switch (reason) {
      case 'notYourTurn':
        return '还没轮到你';
      case 'format':
        return '单词只能由英文字母组成';
      case 'duplicate':
        return '单词已重复';
      case 'invalid':
        return '不是有效的英文单词';
      default:
        return '单词未被接受，请换一个试试';
    }
  }

  /// 构造提交结果回执（仅发给提交者；拒绝时携带原因，null-aware 元素自动省略）
  NetMessage _resultMessage(bool ok, String? reason) => NetMessage(
        type: NetMessageType.wordResult,
        payload: {'ok': ok, 'reason': ?reason},
      );

  @override
  void dispose() {
    // 页面销毁即退出对局：关闭底层房间连接
    // （房主解散会通知全员，客户端退出会让房主跳过自己的回合）
    _client?.removeListener(_onClientChanged);
    _host?.close();
    _client?.close();
    super.dispose();
  }
}
