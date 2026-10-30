import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../network/api_client.dart';
import '../session.dart';
import '../ui/theme.dart';
import '../util/formatters.dart';
import 'transfer_page.dart';

/// 磁力链接落地页：在外部点击 magnet: 链接打开 app 时直接进入的独立
/// 页面（不再叠加在主页上的底部面板）。只支持磁力链接（页面仅校验
/// btih 磁链，提交成功后直接跳转任务进度页——替换本页，返回键回主
/// 页），取消则返回主页
class MagnetPage extends StatefulWidget {
  const MagnetPage({super.key, required this.link});

  final String link;

  @override
  State<MagnetPage> createState() => _MagnetPageState();
}

class _MagnetPageState extends State<MagnetPage> {
  bool _submitting = false;
  String? _error;

  /// 标准化磁链（仅 btih）；null 表示不是有效的 btih 磁链，禁止提交
  late final String? _btih = shortMagnet(widget.link);

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final j = await Session.instance.client
          .offlineAddTaskUrls(widget.link);
      if (!mounted) return;
      // 顶层 state=true 且 data[] 每条都成功才算成功
      final results = (j['data'] as List? ?? const []);
      String? failMsg;
      String? addedHash;
      for (final r in results) {
        if (r is Map && r['state'] != true) {
          failMsg = '${r['message'] ?? '任务添加失败'}';
          break;
        }
        // 添加接口带回的 info_hash：任务页靠它精确锁定刚添加的任务
        //（列表把失败任务排最前，按位置找不可靠）
        if (r is Map && r['info_hash'] != null) {
          addedHash = '${r['info_hash']}';
        }
      }
      if (failMsg != null) {
        setState(() {
          _submitting = false;
          _error = failMsg;
        });
        return;
      }
      // 成功：直接进任务进度页（替换本页，返回键回主页）；
      // 开了「云下载后自动打开」则带上标记，任务页等完成后自动打开
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => TransferPage(
              autoOpen: Session.instance.autoOpenAfterDownload,
              watchHash: addedHash)));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '网络异常，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('添加到云下载')),
      body: SafeArea(
        top: false,
        child: Center(
          // 内容整体居中；小屏/长链接/报错文案过长时滚动防溢出
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                const SizedBox(height: 28),
                _linkBox(),
                const SizedBox(height: 16),
                _locationRow(),
                const SizedBox(height: 32),
                if (_error != null || _btih == null) ...[
                  Text(
                      _error ??
                          '该链接不是有效的磁力链接，仅支持 magnet:?xt=urn:btih:…',
                      style: TextStyle(
                          color: AppTheme.accentDeep, fontSize: 13)),
                  const SizedBox(height: 16),
                ],
                _submitButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.cloud_download_outlined,
              color: AppTheme.primary, size: 32),
        ),
        const SizedBox(height: 12),
        const Text('添加到云下载',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('仅支持磁力链接',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
      ],
    );
  }

  Widget _linkBox() {
    // 只展示必要部分（magnet:?xt=urn:btih:…），dn/tr 等参数不显示
    final shown = _btih ?? widget.link;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.scaffold,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              shown,
              maxLines: 3,
              style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              // 复制所展示的短链（与显示一致）
              Clipboard.setData(ClipboardData(text: shown));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('已复制磁力链接'),
                    duration: Duration(seconds: 1)),
              );
            },
            child: Icon(Icons.copy,
                size: 18, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _locationRow() {
    return Row(
      children: [
        Icon(Icons.folder_outlined, size: 18, color: AppTheme.textSecondary),
        const SizedBox(width: 6),
        Text('保存位置', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        const Spacer(),
        Text('根目录', style: TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
      ],
    );
  }

  Widget _submitButton() {
    return SizedBox(
      height: 46,
      child: ElevatedButton(
        // 非有效磁链时禁用（只能打开磁力链接）
        onPressed: (_submitting || _btih == null) ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: _submitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : const Text('添加云下载', style: TextStyle(fontSize: 15)),
      ),
    );
  }

}
