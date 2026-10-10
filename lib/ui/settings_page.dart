import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

import '../session.dart';
import '../ui/theme.dart';

/// 设置页：主题配色（flex_color_scheme 内置方案，点击弹列表切换）+
/// AppID 本地覆盖（留空 = 使用内置）/ 屏蔽词
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _ctrl;
  late final TextEditingController _blockCtrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: Session.instance.userAppId);
    _blockCtrl =
        TextEditingController(text: Session.instance.blocklist.join('\n'));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _blockCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await Session.instance.setUserAppId(_ctrl.text);
    if (!mounted) return;
    setState(() {}); // 刷新"当前生效"展示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(_ctrl.text.trim().isEmpty
              ? '已恢复内置 AppID'
              : '已保存，下次扫码登录时生效')),
    );
  }

  Future<void> _saveBlocklist() async {
    final words = Session.parseBlocklistInput(_blockCtrl.text);
    await Session.instance.setBlocklist(words);
    if (!mounted) return;
    setState(() {}); // 刷新"当前生效"计数
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              words.isEmpty ? '已清空屏蔽词' : '已保存 ${words.length} 个屏蔽词')),
    );
  }

  /// 主题配色选择弹窗（参考 varus）：方案名 + 4 色圆点预览 + 选中勾，
  /// 点击切换主题（全局即时生效并持久化）
  Future<void> _showSchemeDialog() async {
    final tm = ThemeManager.instance;
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('主题配色'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: tm.schemes.length,
            itemBuilder: (context, index) {
              final scheme = tm.schemes[index];
              final selected = scheme.name == AppTheme.current.name;
              return ListTile(
                dense: true,
                title: Text(scheme.name),
                subtitle: _schemeDots(scheme),
                trailing: selected ? const Icon(Icons.check) : null,
                onTap: () async {
                  await tm.select(scheme);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// 方案预览圆点：primary / primaryContainer / secondary / secondaryContainer
  Widget _schemeDots(FlexSchemeData scheme) {
    final colors = [
      scheme.light.primary,
      scheme.light.primaryContainer,
      scheme.light.secondary,
      scheme.light.secondaryContainer,
    ];
    return Row(
      children: [
        for (final color in colors)
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = Session.instance;
    final usingOverride = s.userAppId.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // 主题配色（flex_color_scheme 内置方案表）：点击弹列表选择，
          // 切换后全局即时生效
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题配色'),
            subtitle: Text(AppTheme.current.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showSchemeDialog,
          ),
          Divider(height: 1, color: AppTheme.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('AppID',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: '留空使用内置 AppID',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary),
                  onPressed: _save,
                  child: const Text('保存'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () {
                    _ctrl.clear();
                    _save();
                  },
                  child: const Text('恢复内置'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              '当前生效：${s.appId}'
              '${usingOverride ? '（本地覆盖）' : '（内置）'}',
              style:
                  TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'AppID 即 115 开放平台 client_id，仅保存在本机；'
              '修改后重新扫码登录时使用。',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
          Divider(height: 1, color: AppTheme.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('屏蔽词',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _blockCtrl,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '每行一个，也可用逗号分隔',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary),
                  onPressed: _saveBlocklist,
                  child: const Text('保存'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () {
                    _blockCtrl.clear();
                    _saveBlocklist();
                  },
                  child: const Text('清空'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              '当前生效：${s.blocklist.length} 个屏蔽词',
              style:
                  TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '名字包含任一屏蔽词的文件/文件夹不再显示'
              '（文件列表与搜索结果，大小写不敏感）；仅保存在本机。',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
