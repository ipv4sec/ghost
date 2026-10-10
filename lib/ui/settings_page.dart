import 'package:flutter/material.dart';

import '../session.dart';
import '../ui/theme.dart';

/// 设置页：主题选择 + AppID 本地覆盖（留空 = 使用内置）/ 屏蔽词
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

  /// 主题选择行：色卡 5 圆点 + 名称，右侧选中勾
  Widget _themeRow(GhostPalette p) {
    final selected = p == AppTheme.current;
    return InkWell(
      onTap: () async {
        await ThemeManager.instance.select(p);
        if (mounted) setState(() {}); // 刷新选中勾（页面其余处随全局重建变色）
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            for (final c in p.swatches) ...[
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black12),
                ),
              ),
              const SizedBox(width: 4),
            ],
            const SizedBox(width: 8),
            Expanded(
              child: Text(p.name,
                  style: TextStyle(fontSize: 16, color: AppTheme.textPrimary)),
            ),
            Icon(Icons.check,
                size: 20,
                color: selected ? AppTheme.primary : Colors.transparent),
          ],
        ),
      ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('主题',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
          ),
          // 12 套主题（配色.png 9 张 + 配色1.png 1 张 + 直接给出的 4 色 2 张）：
          // 圆点预览 + 名称，点按切换
          ...ghostPalettes.map(_themeRow),
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
