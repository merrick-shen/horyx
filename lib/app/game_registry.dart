import 'package:horyx/shared/game/game_info.dart';
import 'package:horyx/shared/storage/archive_storage.dart';
import 'package:horyx/games/chess/pages/chess_online_page.dart';
import 'package:horyx/games/chess/pages/chess_page.dart';
import 'package:horyx/games/chess/services/chess_storage.dart';
import 'package:horyx/games/gomoku/pages/gomoku_online_page.dart';
import 'package:horyx/games/gomoku/pages/gomoku_page.dart';
import 'package:horyx/games/gomoku/services/gomoku_storage.dart';
import 'package:horyx/games/scoreboard/pages/scoreboard_page.dart';
import 'package:horyx/games/scoreboard/services/scoreboard_storage.dart';
import 'package:horyx/games/tank/pages/tank_online_page.dart';
import 'package:horyx/games/tank/pages/tank_page.dart';
import 'package:horyx/games/tank/services/tank_storage.dart';
import 'package:horyx/games/word_pk/pages/word_pk_online_page.dart';
import 'package:horyx/games/word_pk/pages/word_pk_page.dart';
import 'package:horyx/games/word_pk/services/word_pk_storage.dart';

/// 游戏注册中心：所有游戏的单一事实来源（组合根）。
/// 位于 app 层：注册表需引用全部游戏页面，放 shared 会让最底层
/// 模块反向依赖所有上层游戏；
/// game_info.dart 纯数据模型保留 shared 供各层使用。
/// 名称/图标等注册数据以各游戏页面常量为源（游戏模块与注册表、
/// 建房入口共用同一常量），本类只做汇总登记。
/// 新增/恢复游戏只需在此登记一处，首页入口、房间图标、客户端联机
/// 跳转与存档管理页条目均自动生效（无需再改各 UI 层的硬编码映射）
abstract final class GameRegistry {
  /// 单词PK
  static final GameInfo wordPk = GameInfo(
    name: WordPkPage.gameName,
    description: '轮流拼写英文单词，考验词汇量的回合对决',
    icon: WordPkPage.gameIcon,
    pageBuilder: (context) => const WordPkPage(),
    onlineClientBuilder: (context, client) =>
        WordPkOnlinePage.client(client: client),
    archive: _archiveInfo(WordPkStorage.instance),
  );

  /// 五子棋
  static final GameInfo gomoku = GameInfo(
    name: GomokuPage.gameName,
    description: '黑白轮流落子，先连成五子者胜',
    icon: GomokuPage.gameIcon,
    pageBuilder: (context) => const GomokuPage(),
    onlineClientBuilder: (context, client) =>
        GomokuOnlinePage.client(client: client),
    archive: _archiveInfo(GomokuStorage.instance),
  );

  /// 坦克动荡
  /// 随机迷宫实时对战：被击毁后结算计分，持续对分（无总局数上限）。
  /// 联机为房主权威模拟 + 状态快照广播（客户端影子战场），详见
  /// lib/games/tank/services/tank_online_controller.dart
  static final GameInfo tank = GameInfo(
    name: TankPage.gameName,
    description: '驾驶坦克走位射击，与好友一决高下',
    icon: TankPage.gameIcon,
    pageBuilder: (context) => const TankPage(),
    onlineClientBuilder: (context, client) =>
        TankOnlinePage.client(client: client),
    archive: _archiveInfo(TankStorage.instance),
  );

  /// 中国象棋
  /// 本地完整对局 + 局域网联机（房主权威校验走子，详见
  /// lib/games/chess/services/chess_online_controller.dart）
  static final GameInfo chess = GameInfo(
    name: ChessPage.gameName,
    description: '楚河汉界双人对弈，将死对方取胜',
    icon: ChessPage.gameIcon,
    pageBuilder: (context) => const ChessPage(),
    onlineClientBuilder: (context, client) =>
        ChessOnlinePage.client(client: client),
    archive: _archiveInfo(ChessStorage.instance),
  );

  /// 计分器（纯本地工具，无联机对局页）
  static final GameInfo scoreboard = GameInfo(
    name: ScoreboardPage.gameName,
    description: '运动计分板，支持主流运动项目',
    icon: ScoreboardPage.gameIcon,
    pageBuilder: (context) => const ScoreboardPage(),
    archive: _archiveInfo(ScoreboardStorage.instance),
  );

  /// 首页游戏列表（全部已上架游戏）
  static final List<GameInfo> games = [
    wordPk,
    gomoku,
    tank,
    chess,
    scoreboard,
  ];

  /// 按名称查找游戏；未登记返回 null
  static GameInfo? byName(String name) {
    for (final game in games) {
      if (game.name == name) return game;
    }
    return null;
  }
}

/// 由具体类型的存档服务构造存档管理适配（读取最新档 + 按 id 删除）。
/// 各游戏状态模型均实现展示契约，故可统一收敛到非泛型条目视图，
/// 注册表登记处免写逐游戏的闭包样板
GameArchiveInfo _archiveInfo<A extends GameArchiveSummary>(
  ArchiveStorage<A> storage,
) {
  return GameArchiveInfo(
    loadLatest: () async {
      final record = await storage.loadLatest();
      if (record == null) return null;
      return GameArchiveEntry(id: record.id, summary: record.state);
    },
    remove: storage.remove,
  );
}
