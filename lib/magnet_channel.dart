import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 磁力链接信箱：接收原生侧（channel: ghost/intent）转发的 magnet: 链接。
///
/// - 冷启动带入 / 热启动点击都汇入 [pending]
/// - 未登录时暂存（单例），登录进入 HomeShell 后再弹添加面板
/// - 面板处理完由消费方调 [consume] 清除
class MagnetInbox extends ChangeNotifier {
  MagnetInbox._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onMagnetLink') accept('${call.arguments}');
    });
  }

  static final MagnetInbox instance = MagnetInbox._();

  static const _channel = MethodChannel('ghost/intent');

  String? _pending;

  /// 待处理的磁链；同一时间只保留最新一条
  String? get pending => _pending;

  /// 冷启动：MainActivity onCreate 捕获的链接由 Dart 侧主动拉取。
  /// 不论登录与否都拉（未登录则暂存，登录后由 HomeShell 处理）
  Future<void> init() async {
    try {
      final link = await _channel.invokeMethod<String>('getInitialLink');
      if (link != null && link.isNotEmpty) accept(link);
    } on PlatformException {
      // 原生通道异常忽略（冷启动磁链丢失可接受，热启动路径仍可用）
    } on MissingPluginException {
      // 非 Android 平台忽略
    }
  }

  /// 收到磁链：覆盖旧值并通知监听者（HomeShell 弹面板）
  void accept(String link) {
    if (!link.startsWith('magnet:')) return;
    _pending = link;
    notifyListeners();
  }

  /// 面板处理完成后清除
  void consume() {
    if (_pending == null) return;
    _pending = null;
    notifyListeners();
  }
}
