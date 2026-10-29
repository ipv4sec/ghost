import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

import '../session.dart';
import '../ui/theme.dart';
import '../util/backup_service.dart';
import '../util/formatters.dart';
import 'tv.dart';

/// 设置页：主题配色（flex_color_scheme 内置方案，点击弹列表切换）+
/// 界面字体 / 云下载后自动打开 / AppID 本地覆盖 / 屏蔽词 / 备份与恢复
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  late final TextEditingController _ctrl;
  late final TextEditingController _blockCtrl;
  BackupStatus? _bk;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: Session.instance.userAppId);
    _blockCtrl =
        TextEditingController(text: Session.instance.blocklist.join('\n'));
    WidgetsBinding.instance.addObserver(this);
    _refreshBk();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    _blockCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统「所有文件访问」授权页返回时刷新备份状态
    if (state == AppLifecycleState.resumed) _refreshBk();
  }

  Future<void> _refreshBk() async {
    final st = await BackupService.instance.status();
    if (mounted) setState(() => _bk = st);
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

  Future<void> _backupNow() async {
    final ok = await BackupService.instance.saveNow();
    await _refreshBk();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? '已备份：${_bk?.path ?? ''}'
            : '备份失败：${BackupService.instance.lastError ?? '未知原因'}')));
  }

  Future<void> _deleteBackup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除备份'),
        content: const Text('将删除外部存储根目录的 .ghost.json 备份文件；卸载重装后无法自动登录。'),
        actions: [
          TextButton(
            // 电视：聚焦「取消」防误触（同退出登录弹窗惯例）
            autofocus: Tv.isTv,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.current.light.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await BackupService.instance.clear();
      await _refreshBk();
    }
  }

  Future<void> _grantPerm() async {
    final b = BackupService.instance;
    if ((await b.permissionStatus()).mode == BackupPermMode.runtime) {
      // API<=29：系统弹窗，原地等结果
      await b.requestRuntimePermission();
    } else {
      // API 30+：跳设置页，resumed 时 observer 再刷新
      await b.openAllFilesAccessSettings();
    }
    await _refreshBk();
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
                // 电视：弹窗打开聚焦当前配色，方向键就近切换
                autofocus: Tv.isTv && selected,
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

  /// 字体选择弹窗（同主题配色交互）：Montserrat / 系统字体，
  /// 点击全局即时生效
  Future<void> _showFontDialog() async {
    final tm = ThemeManager.instance;
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('界面字体'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in AppFont.all)
              ListTile(
                dense: true,
                // 电视：弹窗打开聚焦当前字体
                autofocus: Tv.isTv && f == AppTheme.font,
                title: Text(f.label),
                trailing: f == AppTheme.font ? const Icon(Icons.check) : null,
                onTap: () async {
                  await tm.selectFont(f);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
              ),
          ],
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
          // 界面字体：Montserrat（中文回退微软正黑体）/ 系统字体
          ListTile(
            leading: const Icon(Icons.font_download_outlined),
            title: const Text('界面字体'),
            subtitle: Text(AppTheme.font.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showFontDialog,
          ),
          Divider(height: 1, color: AppTheme.divider),
          // 云下载后自动打开：开启后从磁力页提交云下载，任务页等任务
          // 完成即自动打开保存位置（盯列表最新一条，失败则不再等待）
          SwitchListTile(
            value: s.autoOpenAfterDownload,
            // 本页不监听 Session，改完需 setState 刷新开关显示
            onChanged: (v) async {
              await s.setAutoOpenAfterDownload(v);
              if (mounted) setState(() {});
            },
            title: const Text('云下载后自动打开'),
            subtitle: const Text('提交云下载后等待完成，自动打开保存位置'),
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
              '（文件列表与搜索结果，大小写不敏感）；随设置备份到 .ghost.json。',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
          Divider(height: 1, color: AppTheme.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('备份与恢复',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: Text(_bk?.exists == true ? '备份文件已就绪' : '暂无备份文件'),
            subtitle: Text(
              [
                _bk?.path ?? '…',
                if (_bk?.lastSavedAt != null)
                  '最近备份 ${fmtDate(DateTime.fromMillisecondsSinceEpoch(_bk!.lastSavedAt!))}'
                else
                  '尚未备份',
                _bk?.perm.granted == true
                    ? '存储权限已授予'
                    : '未授予存储权限（卸载重装后无法自动恢复）',
              ].join('\n'),
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary),
                  onPressed: _backupNow,
                  child: const Text('立即备份'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _deleteBackup,
                  child: const Text('删除备份'),
                ),
                if (_bk != null && !_bk!.perm.granted) ...[
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _grantPerm,
                    child: const Text('去授权'),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '登录凭证与本地设置自动备份为明文 JSON，存放在外部存储根目录'
              '隐藏文件 .ghost.json（卸载不清除，重装后自动恢复）；能读取该'
              '文件的人均可获取凭证，退出登录时自动删除。',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
