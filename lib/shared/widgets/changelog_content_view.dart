import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/update/changelog_parser.dart';

/// 更新内容统一渲染视图：类型分组 + 条目列表（可带子项）+ 行内格式
/// 更新日志详情页与更新弹窗共用，两处视觉呈现严格一致；
/// 条目文本支持行内格式：`代码` 等宽高亮、URL 自动识别为可点击链接
class ChangelogContentView extends StatelessWidget {
  const ChangelogContentView({super.key, required this.sections});

  final List<ChangelogSection> sections;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分组间距 20 与详情页版式一致；首组前不加间距，由调用方控制顶部留白
        for (final (index, section) in sections.indexed) ...[
          if (index > 0) const SizedBox(height: 20),
          _buildSection(palette, section),
        ],
      ],
    );
  }

  /// 单个类型分组：类型标题 + 条目列表
  Widget _buildSection(AppPalette palette, ChangelogSection section) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.typeName,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ...section.items.map((item) => _buildItem(palette, item)),
      ],
    );
  }

  /// 单条变更记录：主项 + 可选子项（如四个游戏的明细）
  Widget _buildItem(AppPalette palette, ChangelogItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 主题色小圆点作为主列表符号
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(top: 7),
                decoration: BoxDecoration(
                  color: palette.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChangelogInlineText(
                  item.text,
                  style: TextStyle(color: palette.textPrimary, fontSize: 13.5),
                ),
              ),
            ],
          ),
          // 子项：整体左缩进，符号用浅色小圆点与主项区分层级
          ...item.children.map(
            (child) => Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: palette.textSecondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ChangelogInlineText(
                      child,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 支持行内格式的文本：`代码` 等宽高亮、URL 可点击
/// 链接点击跳转系统浏览器，失败静默（说明文本中的链接是附加能力，不弹错误打扰）
class ChangelogInlineText extends StatefulWidget {
  const ChangelogInlineText(this.text, {super.key, required this.style});

  final String text;

  /// 基础文字样式（颜色/字号由调用方定），代码与链接样式在其上派生
  final TextStyle style;

  @override
  State<ChangelogInlineText> createState() => _ChangelogInlineTextState();
}

/// 行内格式词法：`代码段` 或 http(s) 链接
final _inlinePattern = RegExp(r'`([^`]+)`|(https?://[^\s`]+)');

/// 链接尾部需要剥离的标点（正文里链接常紧跟句号、括号等）
const _urlTrailingPunctuation = '.,;:!?、。，；：！？）)』」》>';

class _ChangelogInlineTextState extends State<ChangelogInlineText> {
  final _linkRecognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final recognizer in _linkRecognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = widget.style;

    // 每次构建重建手势识别器，先释放上一轮的，避免泄露
    for (final recognizer in _linkRecognizers) {
      recognizer.dispose();
    }
    _linkRecognizers.clear();

    // 行内代码：等宽字体 + 主题色 + 淡色底，字号略小与正文协调
    final codeStyle = style.copyWith(
      fontFamily: 'monospace',
      color: palette.primary,
      fontSize: (style.fontSize ?? 13) - 1,
      background: Paint()..color = palette.primary.withValues(alpha: 0.08),
    );
    // 链接：主题色 + 下划线，与代码段区分
    final linkStyle = style.copyWith(
      color: palette.primary,
      decoration: TextDecoration.underline,
    );

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in _inlinePattern.allMatches(widget.text)) {
      final code = match.group(1);
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }
      if (code != null) {
        spans.add(TextSpan(text: code, style: codeStyle));
      } else {
        // 剥离链接尾部标点，避免点击跳转到带句号的坏地址
        var url = match.group(0)!;
        while (url.isNotEmpty &&
            _urlTrailingPunctuation.contains(url[url.length - 1])) {
          url = url.substring(0, url.length - 1);
        }
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _launchUrl(url);
        _linkRecognizers.add(recognizer);
        spans.add(TextSpan(text: url, style: linkStyle, recognizer: recognizer));
        // 被剥离的标点保留为普通文本
        final trailing = widget.text.substring(match.start + url.length, match.end);
        if (trailing.isNotEmpty) {
          spans.add(TextSpan(text: trailing));
        }
      }
      cursor = match.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    return Text.rich(
      TextSpan(children: spans),
      style: style,
    );
  }

  Future<void> _launchUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // 无可处理的应用或地址非法时静默，不打扰用户
    }
  }
}
