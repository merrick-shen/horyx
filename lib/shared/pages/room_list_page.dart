import 'package:flutter/material.dart';

import 'package:horyx/shared/pages/room_page.dart';
import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/widgets/alert_dialog.dart';
import 'package:horyx/shared/widgets/app_page_scaffold.dart';
import 'package:horyx/shared/widgets/app_text_field.dart';
import 'package:horyx/shared/widgets/panel_card.dart';
import 'package:horyx/shared/widgets/page_content.dart';
import 'package:horyx/shared/widgets/primary_button.dart';

/// 局域网加入房间页（「联机」tab 常驻页）
/// 输入房主在房间等待页显示的地址（IP:端口）直接加入；
/// 连接与入座流程由房间等待页负责
class RoomListPage extends StatefulWidget {
  const RoomListPage({super.key});

  @override
  State<RoomListPage> createState() => _RoomListPageState();
}

class _RoomListPageState extends State<RoomListPage> {
  /// 房主地址输入框
  final _addressController = TextEditingController();

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  /// 加入房间：校验通过后进入等待页并连接房主，格式有误弹窗提示
  /// 加入前无法得知房主开设的游戏，满员后由等待页按握手应答中的
  /// 游戏名解析联机对局页构建器跳转
  void _join() {
    // 收起键盘：无论加入还是弹窗提示，返回/关闭后键盘都不应残留
    FocusScope.of(context).unfocus();
    final address = _parseAddress(_addressController.text);
    if (address == null) {
      showAlertDialog(context, message: '请输入正确的 IP:端口');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RoomPage.client(address: address.host, port: address.port),
      ),
    );
  }

  /// 解析地址输入：必须为 `IP:端口` 形式，两者均必填——
  /// 房主等待页展示与复制的地址即此格式，直接粘贴可用
  /// 格式非法（含缺少端口的单独 IP）返回 null，由调用方给出错误提示
  ({String host, int port})? _parseAddress(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return null;
    // IPv6 含多个冒号，超出「IP:端口」一格的格式直接判非法
    final parts = input.split(':');
    if (parts.length != 2) return null;
    final portValue = int.tryParse(parts[1]);
    if (!_isValidIpv4(parts[0]) ||
        portValue == null ||
        portValue < 1 ||
        portValue > 65535) {
      return null;
    }
    return (host: parts[0], port: portValue);
  }

  /// IPv4 格式校验：四段 0-255 的数字
  bool _isValidIpv4(String value) {
    final segments = value.split('.');
    if (segments.length != 4) return false;
    for (final segment in segments) {
      if (segment.isEmpty || segment.length > 3) return false;
      final number = int.tryParse(segment);
      if (number == null || number < 0 || number > 255) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AppPageScaffold(
      title: '加入房间',
      child: PageContent(
        scrollable: true,
        child: Column(
          children: [
            // 顶部视觉锚点：主题色淡底圆角图标块（与房间卡图标同风格）
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: palette.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.lan_rounded,
                color: palette.primary,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '输入房主地址加入对局',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '与好友连接同一 Wi-Fi，地址可在房主的房间等待页一键复制',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '房主地址',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _addressController,
                    // 地址输入无联想与纠错需求，回车直接提交
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _join(),
                    decoration: buildAppTextFieldDecoration(
                      palette,
                      hintText: '例如 192.168.124.3:45654',
                      fillColor: palette.scaffoldBg,
                    ),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: '加入房间',
                    icon: Icons.login_rounded,
                    onPressed: _join,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
