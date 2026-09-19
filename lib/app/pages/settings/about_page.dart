import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/update/download_launcher.dart';
import 'package:horyx/shared/update/update_service.dart';
import 'package:horyx/shared/widgets/alert_dialog.dart';
import 'package:horyx/shared/widgets/app_page_scaffold.dart';
import 'package:horyx/shared/widgets/update_available_dialog.dart';
import 'package:horyx/app/pages/settings/changelog_page.dart';
import 'package:horyx/app/pages/settings/oss_licenses_page.dart';

/// 关于页
/// 展示应用图标、名称、简介与版本号（版本号读取自 pubspec，自动同步），
/// 并提供检查更新入口（GitHub Release 检测）
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

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

  /// 检查更新：三态反馈——有新版弹窗（可跳转下载）、版本相同与失败走提示条
  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    final result = await _updateService.check();
    if (!mounted) return;
    setState(() => _checking = false);

    switch (result) {
      case UpdateAvailable(:final release):
        final download = await showUpdateAvailableDialog(
          context,
          release: release,
        );
        if (!mounted || !download) return;
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
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 应用标识：主题色 Logo
              // （SVG 源文件为黑色填充，经 colorFilter 重着色，
              //   颜色实时跟随用户选择的主题色）
              SvgPicture.asset(
                'assets/icon/logo.svg',
                width: 90,
                height: 90,
                colorFilter: ColorFilter.mode(
                  palette.primary,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Horyx',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '游戏合集，随时开局的掌上游戏厅',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13.5,
                ),
              ),
              if (_version.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text(
                  'v$_version 开发版',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              // 检查更新与更新日志两个入口同宽：IntrinsicWidth 取两行
              // 最宽者，stretch 拉伸使两按钮等宽对齐
              IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 检查更新入口：检查中转圈并禁点
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _checking ? null : _checkUpdate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: palette.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_checking)
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: palette.primary,
                                ),
                              )
                            else
                              Icon(
                                Icons.system_update_rounded,
                                size: 18,
                                color: palette.primary,
                              ),
                            const SizedBox(width: 6),
                            Text(
                              _checking ? '检查中…' : '检查更新',
                              style: TextStyle(
                                color: palette.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 更新日志入口：内容较长，跳转独立页滚动浏览
                    // （内容读取自打包的 CHANGELOG.md，与仓库文件一致）
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ChangelogPage(),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: palette.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.article_outlined,
                              size: 18,
                              color: palette.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '更新日志',
                              style: TextStyle(
                                color: palette.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: palette.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 开源许可入口：展示应用所用全部开源库的许可证（合规声明）
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const OssLicensesPage(),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: palette.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.balance_outlined,
                              size: 18,
                              color: palette.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '开源许可',
                              style: TextStyle(
                                color: palette.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: palette.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Text(
                '开发者：Merrick Shen',
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
