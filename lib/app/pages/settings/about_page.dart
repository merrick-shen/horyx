import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/update/download_launcher.dart';
import 'package:horyx/shared/update/update_service.dart';
import 'package:horyx/shared/widgets/alert_dialog.dart';
import 'package:horyx/shared/widgets/app_page_scaffold.dart';
import 'package:horyx/shared/widgets/page_content.dart';
import 'package:horyx/shared/widgets/panel_card.dart';
import 'package:horyx/shared/widgets/setting_tile.dart';
import 'package:horyx/shared/widgets/update_available_dialog.dart';
import 'package:horyx/app/pages/settings/changelog_page.dart';
import 'package:horyx/app/pages/settings/oss_licenses_page.dart';

/// 关于页
/// 展示应用图标、名称、简介与版本号（版本号读取自 pubspec，自动同步），
/// 并提供检查更新入口（GitHub Release 检测）
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  /// 项目仓库地址（关于页入口展示与跳转）
  static const String repositoryUrl =
      'https://github.com/merrick-shen/horyx';

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  final UpdateService _updateService = UpdateService();

  /// 版本号（如 1.0.0）；加载前置空不展示
  String _version = '';

  /// 检查更新进行中：入口转圈并禁点
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  /// 读取应用版本信息
  /// 读取失败（极端平台异常）时保持空串，页面仅省略版本行
  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = info.version);
      }
    } catch (e) {
      // 极端平台异常：记录线索后保持空串，页面仅省略版本行（与注释约定一致）
      debugPrint('读取版本信息失败: $e');
    }
  }

  /// 打开项目仓库：外部浏览器接管，无可处理链接的应用等异常时提示
  Future<void> _openRepository() async {
    try {
      final launched = await launchUrl(
        Uri.parse(AboutPage.repositoryUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (!launched) await showAlertDialog(context, message: '无法打开链接');
    } catch (_) {
      if (mounted) {
        await showAlertDialog(context, message: '无法打开链接');
      }
    }
  }

  /// 检查更新：三态反馈——有新版弹窗（可跳转下载）、版本相同与失败走提示条
  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    final result = await _updateService.check();
    if (!mounted) return;
    setState(() => _checking = false);

    switch (result) {
      case UpdateAvailable(:final release):
        // 手动检查不展示「忽略此版本」，始终弹窗供用户决策
        final choice = await showUpdateAvailableDialog(
          context,
          release: release,
        );
        if (!mounted || choice != UpdateDialogChoice.download) return;
        await launchDownload(context, release);
      case UpdateUpToDate():
        await showAlertDialog(context, message: '当前已是最新版本');
      case UpdateCheckFailed():
        await showAlertDialog(context, message: '检查失败，请检查网络后重试（GitHub 访问可能受限）');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AppPageScaffold(
      title: '关于',
      showBack: true,
      child: SingleChildScrollView(
        child: PageContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 应用标识区：主题色 Logo + 名称 + 简介 + 版本徽章
              // （SVG 源文件为黑色填充，经 colorFilter 重着色，
              //   颜色实时跟随用户选择的主题色）
              const SizedBox(height: 24),
              Center(
                child: Column(
                  children: [
                    SvgPicture.asset(
                      'assets/icon/logo.svg',
                      width: 88,
                      height: 88,
                      colorFilter: ColorFilter.mode(
                        palette.primary,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Horyx',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '游戏合集，随时开局的掌上游戏厅',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13.5,
                      ),
                    ),
                    if (_version.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      // 版本徽章：主题色淡底胶囊，读取自 pubspec 自动同步
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: palette.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(Radii.chip),
                        ),
                        child: Text(
                          'v$_version 开发版',
                          style: TextStyle(
                            color: palette.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),
              // 功能入口卡片：与「更多」页一致的设置行语言
              PanelCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    // 检查更新入口：检查中右侧转圈并禁点（无导航箭头）
                    SettingTile(
                      icon: Icons.system_update_rounded,
                      title: '检查更新',
                      subtitle: '检测并获取最新版本',
                      onTap: _checking ? () {} : _checkUpdate,
                      trailing: _checking
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: palette.primary,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    // 更新日志入口：内容较长，跳转独立页滚动浏览
                    // （内容读取自打包的 CHANGELOG.md，与仓库文件一致）
                    SettingTile(
                      icon: Icons.article_outlined,
                      title: '更新日志',
                      subtitle: '版本历史与功能变更',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ChangelogPage(),
                        ),
                      ),
                    ),
                    // 开源许可入口：展示应用所用全部开源库的许可证（合规声明）
                    SettingTile(
                      icon: Icons.balance_outlined,
                      title: '开源许可',
                      subtitle: '应用所用开源库声明',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const OssLicensesPage(),
                        ),
                      ),
                    ),
                    // 项目仓库入口：外部浏览器打开 GitHub 仓库
                    SettingTile(
                      icon: Icons.code_rounded,
                      title: 'GitHub仓库',
                      subtitle: 'github.com/merrick-shen/horyx',
                      onTap: _openRepository,
                      trailing: Icon(
                        Icons.open_in_new_rounded,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '开发者：Merrick Shen',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
