import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_theme.dart';
import '../widgets/app_top_bar.dart';
import 'changelog_page.dart';

/// 关于页
/// 展示应用图标、名称、简介与版本号（版本号读取自 pubspec，自动同步）
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  /// 版本号（如 1.0.0）；加载前置空不展示
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  /// 读取应用版本信息
  /// 读取失败（极端平台异常）时保持空串，页面仅省略版本行
  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _version = info.version);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 顶栏 + 返回按钮（与各二级页一致）
            AppTopBar(
              title: '关于',
              leading: IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: palette.textPrimary,
                  size: 20,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 应用标识：白色圆角矩形卡片 + 主题色 Logo
                      // （SVG 源文件为黑色填充，经 colorFilter 重着色，
                      //   颜色实时跟随用户选择的主题色）
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: palette.primary.withValues(alpha: 0.35),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: SvgPicture.asset(
                          'assets/icon/logo.svg',
                          width: 90,
                          height: 90,
                          colorFilter: ColorFilter.mode(
                            palette.primary,
                            BlendMode.srcIn,
                          ),
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
                      const SizedBox(height: 26),
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
            ),
          ],
        ),
      ),
    );
  }
}
