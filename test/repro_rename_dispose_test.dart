// 回归测试：验证文本输入对话框"控制器由对话框自持"的修复模式。
// 旧模式（await showDialog 返回后立即 dispose 控制器）会在退出动画期间
// 触发 "A TextEditingController was used after being disposed" 断言。
// 本文件内联了 files_page.dart 中 _TextInputDialog 的同款实现进行验证。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    this.initial = '',
    this.hint,
    this.confirmText = '确定',
  });

  final String title;
  final String initial;
  final String? hint;
  final String confirmText;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    debugPrint('对话框已卸载，控制器此时才 dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: InputDecoration(isDense: true, hintText: widget.hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
            child: Text(widget.confirmText),
          ),
        ],
      );
}

void main() {
  /// 打开对话框并点按钮，返回对话框的弹回值
  Future<String?> runDialog(WidgetTester tester, String action) async {
    final completer = Completer<String?>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                completer.complete(await showDialog<String>(
                  context: context,
                  builder: (ctx) => const _TextInputDialog(
                    title: '重命名',
                    initial: 'old-name',
                    hint: '输入新名称',
                    confirmText: '确定',
                  ),
                ));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    if (action == '确定') {
      await tester.enterText(find.byType(TextField), '  new-name  ');
    }
    await tester.tap(find.text(action));
    await tester.pump(); // pop 完成，退出动画开始
    // 逐帧跑完退出动画——旧模式（pop 后立即 dispose 控制器）在此窗口内
    // 即触发 "used after being disposed" 断言
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    return completer.future;
  }

  testWidgets('取消：退出动画全程不抛异常，返回 null', (WidgetTester tester) async {
    expect(await runDialog(tester, '取消'), isNull);
  });

  testWidgets('确定：返回输入文本（去空白），同样全程不抛异常', (
    WidgetTester tester,
  ) async {
    expect(await runDialog(tester, '确定'), 'new-name');
  });
}
