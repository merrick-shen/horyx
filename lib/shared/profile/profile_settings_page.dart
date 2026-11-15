import 'package:flutter/material.dart';

import 'package:horyx/shared/profile/profile_controller.dart';
import 'package:horyx/shared/theme/app_theme.dart';
import 'package:horyx/shared/widgets/alert_dialog.dart';
import 'package:horyx/shared/widgets/app_page_scaffold.dart';
import 'package:horyx/shared/widgets/app_text_field.dart';
import 'package:horyx/shared/widgets/page_content.dart';
import 'package:horyx/shared/widgets/panel_card.dart';
import 'package:horyx/shared/widgets/primary_button.dart';

/// 名字长度上限；按字素计（emoji/中文均算 1 个）
const int _maxNameGlyphs = 12;

/// 个人资料设置页
/// 编辑用户名（联机时好友可见），保存后全局即时生效并持久化，页面不退出；
/// 保存按钮固定页面底部：无有效改动（输入非法或与当前一致）时呈禁用灰态，
/// 可保存时呈主题色
class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  late final TextEditingController _nameController;
  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Scope 依赖需在 didChangeDependencies 中读取（initState 中不可用）；
    // 仅首次预填当前名字，重建时不可重置输入内容
    if (!_prefilled) {
      _prefilled = true;
      _nameController = TextEditingController(
        text: ProfileScope.of(context).name ?? '',
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 输入合法且与当前名字不同才可保存（重复保存无意义，setName 会跳过）
  bool _canSave() {
    final name = _nameController.text.trim();
    return name.isNotEmpty &&
        name.characters.length <= _maxNameGlyphs &&
        name != ProfileScope.of(context).name;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    // 长度按字素计而非 UTF-16 码元，故不用 TextField 的 maxLength
    if (name.isEmpty || name.characters.length > _maxNameGlyphs) {
      await showAlertDialog(context, message: '名字需为 1-12 个字符');
      return;
    }
    await ProfileScope.of(context).setName(name);
    if (mounted) await showAlertDialog(context, message: '已保存');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AppPageScaffold(
      title: '个人资料',
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: PageContent(
              scrollable: true,
              child: PanelCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '名字',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _nameController,
                      // 不禁用联想/纠错：禁联想的输入框会被小米安全键盘
                      // 当作密码类输入，强制只出英文数字键盘，中文无法输入
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(),
                      decoration: buildAppTextFieldDecoration(
                        palette,
                        hintText: '输入你的名字',
                        fillColor: palette.scaffoldBg,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '1-12 个字符，联机时好友将看到这个名字',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 保存按钮固定页面底部，不随卡片滚动；SafeArea 避让底部手势条
          SafeArea(
            top: false,
            child: PageContent(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: AnimatedBuilder(
                  animation: _nameController,
                  builder: (context, _) {
                    return PrimaryButton(
                      label: '保存',
                      icon: Icons.check_rounded,
                      // 无有效改动时禁用（灰态），可保存时呈主题色
                      onPressed: _canSave() ? _save : null,
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
