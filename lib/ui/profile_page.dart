import 'package:flutter/material.dart';

import '../models/models.dart';
import '../network/api_client.dart';
import '../session.dart';
import '../ui/theme.dart';
import '../util/formatters.dart';
import 'about_page.dart';
import 'settings_page.dart';

/// 用户信息（侧边抽屉内，100% 参照 webp 截图布局）
///
/// - 深蓝头部：圆形头像 + 白色粗体用户名 + 半透明 ID 行
/// - 金色渐变 VIP 卡片（皇冠图标 + 等级文字）
/// - 存储区：蓝色粗进度条 + "已用 X / 总量 Y" 一行灰字
/// - 图标菜单列表（设置/关于；下载入口在主页顶栏），退出登录固定抽屉最底部
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.embedded = true});

  /// 始终嵌在抽屉里（无 AppBar）
  final bool embedded;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with AutomaticKeepAliveClientMixin {
  UserInfo? _user;
  String? _error;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final j = await Session.instance.client.userInfo();
      if (!mounted) return;
      setState(() {
        _user = UserInfo.fromJson(j);
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '网络异常';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    final u = _user!;
    // 退出登录不随内容滚动：列表占满剩余高度，按钮固定抽屉最底部
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _header(u),
              _vipCard(u),
              _storageSection(u),
              _menuSection(u),
            ],
          ),
        ),
        // 避让底部手势条/导航栏
        SafeArea(top: false, child: _logoutButton()),
      ],
    );
  }

  /// 深蓝头部：头像 + 用户名 + ID 行
  Widget _header(UserInfo u) {
    return Container(
      color: AppTheme.primary,
      width: double.infinity,
      // 加高蓝色头部区域，内容贴左下角
      constraints: const BoxConstraints(minHeight: 190),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      alignment: Alignment.bottomLeft,
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white24,
            foregroundImage:
                u.avatar.isNotEmpty ? NetworkImage(u.avatar) : null,
            child: u.avatar.isEmpty
                ? const Icon(Icons.person, size: 32, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.name.isEmpty ? '115 用户' : u.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: ${u.userId}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 粉色渐变 VIP 卡片（皇冠 + 等级/开通），粉色系配色
  Widget _vipCard(UserInfo u) {
    final hasVip = u.vipExpire > 0 && u.vipName != '原石会员';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          // 渐变两端随主题（浅 → 深，配深字）
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [AppTheme.vipStart, AppTheme.vipEnd],
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              hasVip ? Icons.workspace_premium : Icons.workspace_premium_outlined,
              color: AppTheme.textPrimary,
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasVip ? u.vipName : '开通会员',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (hasVip) ...[
                    const SizedBox(height: 2),
                    Text(
                      '有效期至 ${fmtExpire(u.vipExpire)}',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            if (!hasVip)
              Text(
                '畅享更多权益',
                style:
                    TextStyle(color: AppTheme.textPrimary, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }

  /// 存储区：粗进度条 + "已用 X / 总量 Y"
  Widget _storageSection(UserInfo u) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_queue,
                  size: 18, color: AppTheme.primary),
              const SizedBox(width: 6),
              Text('存储空间',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
              const Spacer(),
              Text(
                '${(u.usagePercent * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: u.usagePercent,
              minHeight: 8,
              backgroundColor: AppTheme.divider,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '已用 ${_fmt(u.usedText, u.usedBytes)} / ${_fmt(u.totalText, u.totalBytes)}',
            style: TextStyle(
                fontSize: 13, color: AppTheme.textSecondary),
          ),
          // 第三方畅用权益行——暂时隐藏，恢复时取消注释
          // const SizedBox(height: 4),
          // Text(
          //   '第三方畅用权益：${u.tpRights ? '已开通' : '未开通'}',
          //   style: TextStyle(
          //       fontSize: 11, color: AppTheme.textSecondary),
          // ),
        ],
      ),
    );
  }

  /// size_format 缺失时本地格式化兜底
  String _fmt(String serverText, int bytes) =>
      serverText.isNotEmpty ? serverText : formatBytes(bytes);

  /// 图标菜单列表（设置 + 关于；下载已移至主页顶栏图标）
  Widget _menuSection(UserInfo u) {
    return Column(
      children: [
        Divider(height: 1, color: AppTheme.divider),
        _menuItem(
          icon: Icons.settings_outlined,
          iconColor: AppTheme.textSecondary,
          title: '设置',
          subtitle: 'AppID 等本机配置',
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            );
          },
        ),
        Divider(height: 1, color: AppTheme.divider),
        _menuItem(
          icon: Icons.info_outline,
          iconColor: AppTheme.textSecondary,
          title: '关于',
          subtitle: '115 开放平台第三方客户端',
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutPage()),
            );
          },
        ),
        Divider(height: 1, color: AppTheme.divider),
      ],
    );
  }

  Widget _menuItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15, color: AppTheme.textPrimary)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.textSecondary)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logoutButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFF53F3F),
          side: const BorderSide(color: Color(0xFFF53F3F)),
          minimumSize: const Size.fromHeight(44),
        ),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('退出登录'),
              content: const Text('将清除本机的授权凭证，需要重新扫码登录。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF53F3F)),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('退出'),
                ),
              ],
            ),
          );
          if (ok == true) {
            await Session.instance.forceLogout();
          }
        },
        child: const Text('退出登录'),
      ),
    );
  }
}
