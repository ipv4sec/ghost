import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../network/api_client.dart';
import '../session.dart';
import '../ui/theme.dart';
import 'transfer_page.dart';

/// 磁力链接落地页：在外部点击 magnet: 链接打开 app 时直接进入的独立
/// 页面（不再叠加在主页上的底部面板）。提交成功后直接跳转任务进度页
///（替换本页，返回键回主页），取消则返回主页
class MagnetPage extends StatefulWidget {
  const MagnetPage({super.key, required this.link});

  final String link;

  @override
  State<MagnetPage> createState() => _MagnetPageState();
}

class _MagnetPageState extends State<MagnetPage> {
  bool _submitting = false;
  String? _error;

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
      for (final r in results) {
        if (r is Map && r['state'] != true) {
          failMsg = '${r['message'] ?? '任务添加失败'}';
          break;
        }
      }
      if (failMsg != null) {
        setState(() {
          _submitting = false;
          _error = failMsg;
        });
        return;
      }
      // 成功：直接进任务进度页（替换本页，返回键回主页）
      await Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const TransferPage()));
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
                if (_error != null) ...[
                  Text(_error!,
                      style:
                          const TextStyle(color: AppTheme.accent, fontSize: 13)),
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
            color: AppTheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.cloud_download_outlined,
              color: AppTheme.primary, size: 32),
        ),
        const SizedBox(height: 12),
        const Text('添加到云下载',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _linkBox() {
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
              widget.link,
              maxLines: 3,
              style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.link));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('已复制磁力链接'),
                    duration: Duration(seconds: 1)),
              );
            },
            child: const Icon(Icons.copy,
                size: 18, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _locationRow() {
    return const Row(
      children: [
        Icon(Icons.folder_outlined, size: 18, color: AppTheme.textSecondary),
        SizedBox(width: 6),
        Text('保存位置', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        Spacer(),
        Text('根目录', style: TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
      ],
    );
  }

  Widget _submitButton() {
    return SizedBox(
      height: 46,
      child: ElevatedButton(
        onPressed: _submitting ? null : _submit,
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
