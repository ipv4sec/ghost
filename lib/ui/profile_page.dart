import 'package:flutter/material.dart';

import '../models/models.dart';
import '../network/api_client.dart';
import '../session.dart';
import '../ui/theme.dart';
import '../util/formatters.dart';
import 'about_page.dart';
import 'settings_page.dart';

/// 用户信息（侧边抽屉内）
///
/// - 主题色头部：圆形头像 + 粗体用户名 + 年度会员认证图标
///   + 至臻会员到期时间 / 存储使用情况（方块点阵，行尾与到期行对齐）
/// - 图标菜单列表（设置/关于，图标 + 文字左对齐，间距与左缘留白
///   一致；下载入口在主页顶栏），退出行固定抽屉最底部
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
    // 退出不随内容滚动：列表占满剩余高度，退出行固定抽屉最底部
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _header(u),
              _menuSection(),
            ],
          ),
        ),
        // 避让底部手势条/导航栏
        SafeArea(top: false, child: _logoutSection()),
      ],
    );
  }

  /// VIP 判定（原石会员不算）
  bool _hasVip(UserInfo u) => u.vipExpire > 0 && u.vipName != '原石会员';

  /// 头部：头像 + 用户名 + 年度会员认证图标 + 到期时间/存储使用点阵
  /// （底色用主题顶栏色 header，文字用 onHeader，与主页顶栏一致）
  Widget _header(UserInfo u) {
    final expiry = '至臻会员将于${fmtExpireCn(u.vipExpire)}到期';
    final subStyle = TextStyle(
      color: AppTheme.onHeader.withOpacity(0.6),
      fontSize: 13, // 到期/点阵行整体调大一档（TODO），点阵宽随 textW 自适应
    );
    // 存储点阵：小方块铺满到期行的剩余宽度（行尾与其对齐，
    // 间距 spaceBetween 均分约 2px）；非会员无对照行时固定 10 格。
    // 已用格数四舍五入
    double textW(String s) {
      final tp = TextPainter(
        text: TextSpan(
            text: s,
            style: DefaultTextStyle.of(context).style.merge(subStyle)),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp.width;
    }

    const label = '存储使用情况 ';
    var dotCount = 10;
    var dotsWidth = 10 * 4.0 + 9 * 2.0;
    if (_hasVip(u)) {
      final avail = textW(expiry) - textW(label);
      if (avail >= 4) {
        dotCount = ((avail + 2) / 6).floor();
        dotsWidth = avail;
      }
    }
    final filledDots = (u.usagePercent * dotCount).round().clamp(0, dotCount);
    return Container(
      color: AppTheme.header,
      width: double.infinity,
      // 加高头部区域，内容贴左下角
      constraints: const BoxConstraints(minHeight: 190),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      alignment: Alignment.bottomLeft,
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            // onHeader 在浅色顶栏主题下为深色，半透明底两种主题都成立
            backgroundColor: AppTheme.onHeader.withOpacity(0.12),
            foregroundImage:
                u.avatar.isNotEmpty ? NetworkImage(u.avatar) : null,
            child: u.avatar.isEmpty
                ? Icon(Icons.person, size: 32, color: AppTheme.onHeader)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        u.name.isEmpty ? '115 用户' : u.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.onHeader,
                          fontSize: 18, // varus 抽屉头部字号
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // 年度会员认证小图标
                    if (_hasVip(u)) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.verified,
                          size: 16, color: Color(0xFFF2C14E)),
                    ],
                  ],
                ),
                // 到期时间；其下为存储使用情况：标签 + 方块点阵
                if (_hasVip(u)) ...[
                  const SizedBox(height: 4),
                  Text(expiry, style: subStyle),
                  const SizedBox(height: 5),
                ],
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标签后留一个空格再接点阵
                    Text(label, style: subStyle),
                    // 点阵区固定宽 = 到期行宽 - 标签宽，行尾与到期行对齐
                    SizedBox(
                      width: dotsWidth,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (var i = 0; i < dotCount; i++)
                            Container(
                              width: 4,
                              height: 4,
                              // 已用方块深色、未用方块浅色
                              color: i < filledDots
                                  ? AppTheme.onHeader
                                  : AppTheme.onHeader.withOpacity(0.25),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 图标菜单列表（设置 + 关于；下载已移至主页顶栏图标）。
  /// 设置与头部色块的间距 = 关于与上方分隔线的间距（均为行内边距）
  Widget _menuSection() {
    return Column(
      children: [
        _menuItem(
          icon: Icons.settings_outlined,
          title: '设置',
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
          title: '关于',
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutPage()),
            );
          },
        ),
      ],
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String title,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppTheme.textSecondary),
            // 文字与图标的间距 = 图标距左缘的留白（20）
            const SizedBox(width: 20),
            Text(title,
                style: TextStyle(fontSize: 16, color: AppTheme.textPrimary)),
          ],
        ),
      ),
    );
  }

  /// 底部"退出"行（菜单样式，确认后清凭证回登录页），
  /// 上方分隔线与设置/关于间一致
  Widget _logoutSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, color: AppTheme.divider),
        _menuItem(
          icon: Icons.logout_outlined,
          title: '退出',
          onTap: () async {
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
        ),
      ],
    );
  }
}
