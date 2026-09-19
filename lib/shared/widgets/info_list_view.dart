import 'package:flutter/material.dart';

import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/widgets/page_content.dart';
import 'package:horyx/shared/widgets/panel_card.dart';

/// 通用列表条目数据接口：主标题 + 标题行右侧信息 + 副标题摘要 + 点击回调
/// 组件只认该模型、不感知具体业务；各页面（更新日志、开源许可声明等）
/// 将自己的数据源映射为 InfoListItem 后传入，即可复用完全一致的展示效果
class InfoListItem {
  const InfoListItem({
    required this.title,
    this.trailing,
    this.subtitle,
    this.onTap,
    this.heroTag,
  });

  /// 主标题（品牌强调色、加粗）
  final String title;

  /// 标题行右侧的辅助信息（如发布日期；次要色小字号）
  final String? trailing;

  /// 副标题摘要（次要色，单行超出省略）
  final String? subtitle;

  /// 点击回调；为 null 时无点击水波纹反馈
  final VoidCallback? onTap;

  /// Hero 共享元素标签；提供时标题行参与共享元素过渡（与详情页衔接）
  final Object? heroTag;
}

/// 通用卡片列表：加载态 / 空态 + Scrollbar + 懒加载 ListView + 统一卡片条目
/// 条目样式（PanelCard 容器、标题/副标题字号颜色、间距、圆角、点击反馈）
/// 与更新日志页列表完全一致，供需要同类列表展示的页面直接复用；
/// [items] 为 null 时展示加载动画，空列表时展示 [emptyText] 占位
class InfoListView extends StatelessWidget {
  const InfoListView({
    super.key,
    required this.items,
    this.emptyText = '暂无内容',
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 24),
    this.maxContentWidth = PageContent.maxContentWidth,
  });

  /// 条目列表；null 表示加载中，空列表表示无内容
  final List<InfoListItem>? items;

  /// 列表为空时的占位文案
  final String emptyText;

  /// 列表内边距
  final EdgeInsetsGeometry padding;

  /// 内容最大宽度（与 PageContent 限宽一致的平板/大屏适配）；null 表示不限宽
  final double? maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final list = items;

    if (list == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list.isEmpty) {
      return Center(
        child: Text(
          emptyText,
          style: TextStyle(color: palette.textSecondary, fontSize: 14),
        ),
      );
    }

    Widget content = Scrollbar(
      child: ListView.builder(
        padding: padding,
        itemCount: list.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _InfoListCard(item: list[index]),
        ),
      ),
    );

    final maxWidth = maxContentWidth;
    if (maxWidth != null) {
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: content,
        ),
      );
    }
    return content;
  }
}

/// 单条卡片条目：PanelCard 容器 + InkWell 点击反馈 + 标题/副标题 + 右箭头
class _InfoListCard extends StatelessWidget {
  const _InfoListCard({required this.item});

  final InfoListItem item;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    Widget title = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        // 标题可收缩截断：长包名等长标题超出时省略，不挤占右侧信息与箭头
        Flexible(
          child: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.primary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (item.trailing != null) ...[
          const SizedBox(width: 8),
          Text(
            item.trailing!,
            style: TextStyle(color: palette.textSecondary, fontSize: 12),
          ),
        ],
      ],
    );

    // Hero 包裹层需自带透明 Material，保证共享元素过渡期间文字样式连续
    if (item.heroTag != null) {
      title = Hero(
        tag: item.heroTag!,
        child: Material(type: MaterialType.transparency, child: title),
      );
    }

    return PanelCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: item.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      if (item.subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.subtitle!,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: palette.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
