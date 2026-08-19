import 'package:flutter/material.dart';

import '../../data/game_data.dart';
import '../../services/network/room_client.dart';
import '../../services/network/room_host.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_top_bar.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/panel_card.dart';
import '../../widgets/common/primary_button.dart';

/// 局域网房间等待页（所有游戏通用）
/// 房主模式：由各游戏的设置页创建，实时显示入座情况；
/// 客户端模式：由房间列表页点击加入后进入，负责连接与加入流程展示。
/// 满员开局时通过 [hostGameBuilder]/[clientGameBuilder] 跳转到对应游戏的
/// 联机对局页，并把房间连接的所有权移交过去（由对局页负责关闭）。
/// 未提供构建器的游戏满员后停留在「即将开始」展示（联机能力接入前的过渡态）。

/// 房主侧联机对局页构建器：入参为已满员开局的房主连接
typedef HostGameBuilder = Widget Function(BuildContext context, RoomHost host);

/// 客户端侧联机对局页构建器：入参为收到开局通知的客户端连接
typedef ClientGameBuilder = Widget Function(
  BuildContext context,
  RoomClient client,
);

class RoomPage extends StatefulWidget {
  const RoomPage.host({
    super.key,
    required this.gameName,
    required this.capacity,
    this.hostGameBuilder,
  })  : address = null,
        port = null,
        clientGameBuilder = null;

  const RoomPage.client({
    super.key,
    required this.address,
    required this.port,
    this.gameName,
    this.clientGameBuilder,
  })  : capacity = 0,
        hostGameBuilder = null;

  /// 游戏名称（等待页顶部标识卡展示，如「单词PK」）
  final String? gameName;

  /// 本局总人数（仅房主模式有效，含房主）
  final int capacity;

  /// 房主地址（仅客户端模式有效）
  final String? address;

  /// 房主端口（仅客户端模式有效）
  final int? port;

  /// 满员开局后的对局页构建器（房主模式；null 表示该游戏联机对局未接入）
  final HostGameBuilder? hostGameBuilder;

  /// 满员开局后的对局页构建器（客户端模式；null 表示该游戏联机对局未接入）
  final ClientGameBuilder? clientGameBuilder;

  /// 是否房主模式
  bool get isHost => address == null;

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  RoomHost? _host;
  RoomClient? _client;

  /// 房主监听创建失败（候选端口全部被占用）
  bool _hostStartFailed = false;

  /// 连接所有权是否已移交给对局页（移交后本页销毁不再关闭连接）
  bool _transferred = false;

  @override
  void initState() {
    super.initState();
    if (widget.isHost) {
      _initHost();
    } else {
      _client = RoomClient(host: widget.address!, port: widget.port!)
        ..connect();
      // 满员开局 -> 跳转对局页（监听而非 build 中触发，导航不能发生在构建期）
      _client!.addListener(_onClientChanged);
    }
  }

  /// 房主模式：创建房间开始监听（好友通过房间列表自动发现并加入）
  Future<void> _initHost() async {
    final host = RoomHost(
      gameName: widget.gameName!,
      capacity: widget.capacity,
    );
    final ok = await host.start();
    if (!mounted) return;
    if (!ok) {
      setState(() => _hostStartFailed = true);
      return;
    }
    // 满员开局 -> 跳转对局页
    host.addListener(_onHostChanged);
    setState(() => _host = host);
  }

  /// 房主侧状态变化：满员开局后跳转对局页并移交连接所有权
  void _onHostChanged() {
    final host = _host;
    if (host == null || _transferred) return;
    if (host.gameStarted && widget.hostGameBuilder != null) {
      _transferred = true;
      // pushReplacement 替换本页：对局页成为连接的唯一持有者
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => widget.hostGameBuilder!(context, host),
        ),
      );
    }
  }

  /// 客户端侧状态变化：收到开局通知后跳转对局页并移交连接所有权
  void _onClientChanged() {
    final client = _client;
    if (client == null || _transferred) return;
    if (client.phase == RoomClientPhase.gameStarting &&
        widget.clientGameBuilder != null) {
      _transferred = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => widget.clientGameBuilder!(context, client),
        ),
      );
    }
  }

  @override
  void dispose() {
    _host?.removeListener(_onHostChanged);
    _client?.removeListener(_onClientChanged);
    // 连接所有权未移交对局页时由本页负责关闭（房主解散/客户端退出）
    if (!_transferred) {
      _host?.close();
      _client?.close();
    }
    super.dispose();
  }

  /// 无需弹窗确认即可直接退出的状态：
  /// 房主尚未创建成功、客户端还在连接/已失败/已断开（连接已不存在，离开不影响他人）
  bool get _canLeaveQuietly {
    if (widget.isHost) return _host == null || _hostStartFailed;
    final phase = _client?.phase;
    return phase == null ||
        phase == RoomClientPhase.connecting ||
        phase == RoomClientPhase.failed ||
        phase == RoomClientPhase.disconnected;
  }

  /// 退出请求：影响他人的状态先弹确认（房主关房会踢掉所有玩家）
  Future<void> _requestExit() async {
    if (_canLeaveQuietly) {
      Navigator.of(context).pop();
      return;
    }
    final result = await showConfirmDialog(
      context,
      title: widget.isHost ? '关闭房间？' : '离开房间？',
      message: widget.isHost ? '已加入的玩家将被断开连接' : '离开后需重新加入才能继续',
      confirmLabel: widget.isHost ? '关闭房间' : '离开房间',
    );
    if (!mounted) return;
    if (result == ConfirmResult.confirm) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 拦截系统返回手势，统一走确认流程
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestExit();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppTopBar(
                title: '房间',
                leading: IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: context.palette.textPrimary,
                    size: 20,
                  ),
                  onPressed: _requestExit,
                ),
              ),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  /// 按模式与阶段分发内容视图
  Widget _buildBody() {
    if (widget.isHost) {
      if (_hostStartFailed) {
        return _buildMessageView(
          icon: Icons.error_outline_rounded,
          message: '创建房间失败，端口被占用，请稍后重试',
        );
      }
      final host = _host;
      if (host == null) {
        return _buildLoading('正在创建房间…');
      }
      return ListenableBuilder(
        listenable: host,
        builder: (context, _) => _buildRoomContent(
          capacity: host.capacity,
          seats: host.seats,
          mySeat: 1,
          hint: '好友在「联机」页的房间列表中即可看到并加入本房间',
        ),
      );
    }

    final client = _client!;
    return ListenableBuilder(
      listenable: client,
      builder: (context, _) {
        switch (client.phase) {
          case RoomClientPhase.connecting:
            return _buildLoading('正在连接房间…');
          case RoomClientPhase.failed:
            return _buildMessageView(
              icon: Icons.wifi_off_rounded,
              message: client.failReason,
            );
          case RoomClientPhase.disconnected:
            return _buildMessageView(
              icon: Icons.link_off_rounded,
              message: client.disconnectText,
            );
          case RoomClientPhase.joined:
          case RoomClientPhase.gameStarting:
            return _buildRoomContent(
              capacity: client.capacity,
              seats: client.seats,
              mySeat: client.mySeat,
              hint: '你已加入，是玩家 ${client.mySeat ?? 0}，满员后自动开始',
            );
        }
      },
    );
  }

  /// 加载态：居中转圈 + 文案
  Widget _buildLoading(String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2.5),
          const SizedBox(height: 16),
          Text(
            text,
            style: TextStyle(
              color: context.palette.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// 失败/断开态：图标 + 说明 + 返回按钮
  Widget _buildMessageView({required IconData icon, required String message}) {
    final palette = context.palette;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: palette.textSecondary, size: 36),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: '返回',
              outlined: true,
              onPressed: _requestExit,
            ),
          ],
        ),
      ),
    );
  }

  /// 房间主内容：游戏标识卡 + 座位列表卡片 + 等待状态文案
  /// 房主与客户端共用（[hint] 随模式不同：房主引导好友加入，客户端提示自己的座位）
  Widget _buildRoomContent({
    required int capacity,
    required List<int> seats,
    required int? mySeat,
    required String hint,
  }) {
    final remaining = capacity - seats.length;
    final full = remaining <= 0;
    return SizedBox.expand(
      child: Center(
        // 平板/桌面端限制内容宽度，居中展示
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildGameCard(capacity: capacity),
                const SizedBox(height: 16),
                _buildSeatCard(
                  capacity: capacity,
                  seats: seats,
                  mySeat: mySeat,
                ),
                const SizedBox(height: 16),
                // 等待状态文案：满员与否二态展示
                Text(
                  full ? '全部玩家已就位，即将开始' : '等待 $remaining 名玩家加入…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.palette.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
                // 模式提示文案：房主为加入引导，客户端为座位与开局提示
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.palette.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 游戏标识卡：游戏图标 + 名称 + 局规格，所有游戏通用的房间头部
  /// 图标按游戏名匹配静态数据源；未匹配（未来新游戏未登记）时回退通用图标
  Widget _buildGameCard({required int capacity}) {
    final palette = context.palette;
    final name = widget.gameName ?? '游戏房间';
    final matched = GameData.games.where((g) => g.name == name);
    final icon = matched.isEmpty ? Icons.sports_esports_rounded : matched.first.icon;

    return PanelCard(
      child: Row(
        children: [
          // 游戏图标：品牌色淡底，作为房间视觉锚点
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: palette.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '局域网对战 · $capacity 人局',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 座位列表卡片：头部计数 + 每个座位一行（未入座显示等待占位）
  Widget _buildSeatCard({
    required int capacity,
    required List<int> seats,
    required int? mySeat,
  }) {
    final palette = context.palette;
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '玩家',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // 人数计数徽标
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: palette.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${seats.length}/$capacity',
                  style: TextStyle(
                    color: palette.primary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var seat = 1; seat <= capacity; seat++)
            Padding(
              padding: EdgeInsets.only(bottom: seat < capacity ? 10 : 0),
              child: _SeatTile(
                seat: seat,
                taken: seats.contains(seat),
                mySeat: mySeat,
              ),
            ),
        ],
      ),
    );
  }
}

/// 单个座位行：座位号圆标 + 玩家标识（房主/你）或等待占位
class _SeatTile extends StatelessWidget {
  const _SeatTile({
    required this.seat,
    required this.taken,
    this.mySeat,
  });

  /// 座位号（1..N，1 号固定为房主）
  final int seat;

  /// 该座位是否已有人
  final bool taken;

  /// 自己的座位号（null 表示房主视图外的未知视角，仅房主/客户端页传入）
  final int? mySeat;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isMe = mySeat == seat;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        // 已入座用品牌色淡底突出，空位用页面底色弱化
        color: taken
            ? palette.primary.withValues(alpha: 0.08)
            : palette.scaffoldBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.stroke),
      ),
      child: Row(
        children: [
          // 座位号圆标
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: taken ? palette.primary : Colors.transparent,
              shape: BoxShape.circle,
              border: taken ? null : Border.all(color: palette.stroke),
            ),
            child: Text(
              '$seat',
              style: TextStyle(
                color: taken ? Colors.white : palette.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              taken
                  ? '玩家 $seat${seat == 1 ? ' · 房主' : ''}'
                  : '等待加入…',
              style: TextStyle(
                color: taken ? palette.textPrimary : palette.textSecondary,
                fontSize: 14,
                fontWeight: taken ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          // 自己座位的「你」徽标
          if (isMe)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: palette.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '你',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
