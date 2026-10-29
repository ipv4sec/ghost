import 'package:flutter/services.dart';

/// 电视模式检测（Sony 电视等 Android TV 设备）
///
/// main() 里 `await Tv.init()` 一次性读取原生判定
/// （UiModeManager.currentModeType == UI_MODE_TYPE_TELEVISION，见
/// MainActivity 的 ghost/player 通道），之后各页面同步读 [isTv]
/// 分支电视专属交互（遥控器方向键 seek、行尾 ⋮ 菜单等）。
///
/// 触摸手势全部保留：同一个 APK 手机/电视双端运行，电视只是叠加
/// 遥控器（D-pad）操作与更大的文字。
class Tv {
  Tv._();

  /// 是否运行在电视上（默认 false：判定失败/非 Android 平台按手机处理）
  static bool isTv = false;

  /// 电视上的文字缩放（MaterialApp builder 里包 MediaQuery 用）：
  /// 1.2 → 1.0（用户两轮反馈逐次调小，现与手机端同字号）
  static const double textScale = 1.0;

  /// 启动时读一次原生判定（channel: ghost/player，method: isTv）
  static Future<void> init() async {
    try {
      final v =
          await const MethodChannel('ghost/player').invokeMethod<bool>('isTv');
      isTv = v ?? false;
    } catch (_) {
      // 通道未实现/非 Android 平台：按手机处理
    }
  }
}
