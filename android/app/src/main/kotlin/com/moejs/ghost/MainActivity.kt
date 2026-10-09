package com.moejs.ghost

import android.content.Intent
import android.content.pm.ActivityInfo
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.Surface
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

// 转发系统"点击 magnet: 磁力链接"的 Intent 到 Flutter（channel: ghost/intent）：
// - 冷启动：onCreate 捕获，Dart 侧启动时通过 getInitialLink 拉取
// - 热启动（singleTop 复用）：onNewIntent 实时回调 onMagnetLink
//
// 播放页手势通道（channel: ghost/player）：媒体音量 + 窗口亮度读写 + 方向解锁 +
// 播放常亮。亮度用 window attributes（仅本 Activity 生效，退出播放页恢复跟随
// 系统）；音量走 AudioManager STREAM_MUSIC（系统级，与物理音量键一致）；
// keepScreenOn 播放期间保持屏幕常亮（FLAG_KEEP_SCREEN_ON 仅本窗口生效，
// 免权限，暂停/退出播放页时清除）；
// resetOrientation 解除方向锁/退出播放页时恢复"跟随系统"方向
class MainActivity : FlutterActivity() {
    private var initialLink: String? = null
    private var queuedLink: String? = null
    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initialLink = magnetFrom(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = magnetFrom(intent)
        if (link != null) {
            val ch = channel
            if (ch != null) {
                ch.invokeMethod("onMagnetLink", link)
            } else {
                // 引擎未就绪（极短暂窗口）：暂存，configureFlutterEngine 时补发
                queuedLink = link
            }
        }
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "ghost/intent").also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialLink" -> {
                        val link = initialLink ?: queuedLink
                        initialLink = null
                        queuedLink = null
                        result.success(link)
                    }
                    else -> result.notImplemented()
                }
            }
            queuedLink?.let { link ->
                ch.invokeMethod("onMagnetLink", link)
                queuedLink = null
            }
        }
        setUpPlayerChannel(engine)
    }

    override fun cleanUpFlutterEngine(engine: FlutterEngine) {
        channel = null
        super.cleanUpFlutterEngine(engine)
    }

    private fun magnetFrom(intent: Intent?): String? =
        intent?.dataString?.takeIf { it.startsWith("magnet:") }

    private fun setUpPlayerChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "ghost/player").setMethodCallHandler { call, result ->
            when (call.method) {
                "getVolume" -> result.success(volumeNorm())
                "setVolume" -> {
                    val v = ((call.arguments as? Number)?.toDouble() ?: 0.5).coerceIn(0.0, 1.0)
                    val am = getSystemService(AUDIO_SERVICE) as AudioManager
                    val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    if (max > 0) {
                        try {
                            am.setStreamVolume(
                                AudioManager.STREAM_MUSIC,
                                (v * max).roundToInt(), 0
                            )
                        } catch (_: SecurityException) {
                            // 部分设备/勿扰策略下禁改音量，忽略
                        }
                    }
                    result.success(null)
                }
                "getBrightness" -> result.success(brightnessNorm())
                "setBrightness" -> {
                    val v = ((call.arguments as? Number)?.toDouble() ?: 0.5).coerceIn(0.0, 1.0)
                    window.attributes = window.attributes.also { it.screenBrightness = v.toFloat() }
                    result.success(null)
                }
                "resetBrightness" -> {
                    // -1 = BRIGHTNESS_VALUE_NONE：恢复跟随系统亮度
                    window.attributes = window.attributes.also { it.screenBrightness = -1f }
                    result.success(null)
                }
                "lockCurrentOrientation" -> {
                    // 播放页方向锁：固定为当前显示方向（横屏锁横屏、竖屏锁
                    // 竖屏），传感器不再生效。旋转值：0=竖屏 90=横屏
                    // 180=倒竖屏 270=反向横屏
                    requestedOrientation = when (displayRotation()) {
                        Surface.ROTATION_90 -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                        Surface.ROTATION_180 -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT
                        Surface.ROTATION_270 -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
                        else -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    }
                    result.success(null)
                }
                "keepScreenOn" -> {
                    // 播放期间屏幕常亮：只影响本窗口，不改系统设置、无需权限；
                    // 暂停（系统超时可正常熄屏省电）与退出播放页时传 false 清除
                    if (call.arguments as? Boolean ?: true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                "resetOrientation" -> {
                    // 退出播放页/解锁方向锁：恢复跟随系统（UNSPECIFIED）。
                    // 不能用 SystemChrome 传全方向替代：引擎会把全方向映射成
                    // SENSOR_LANDSCAPE/SENSOR_PORTRAIT，不是真正的"跟随系统"
                    requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /// 当前窗口旋转值（defaultDisplay 自 API 30 起弃用但全版本可用）
    @Suppress("DEPRECATION")
    private fun displayRotation(): Int = windowManager.defaultDisplay.rotation

    /// 当前媒体音量归一化 0..1
    private fun volumeNorm(): Double {
        val am = getSystemService(AUDIO_SERVICE) as AudioManager
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max <= 0) return 0.0
        return am.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max
    }

    /// 当前亮度归一化 0..1：优先取 window 已设值，否则读系统设置
    private fun brightnessNorm(): Double {
        val cur = window.attributes.screenBrightness
        if (cur >= 0f) return cur.toDouble()
        return try {
            if (Build.VERSION.SDK_INT >= 33) {
                // SCREEN_BRIGHTNESS_FLOAT 常量需 API 33，低 compileSdk 时用字面量
                Settings.System.getFloat(
                    contentResolver, "screen_brightness_float", 0.5f
                ).toDouble()
            } else {
                Settings.System.getInt(
                    contentResolver, Settings.System.SCREEN_BRIGHTNESS
                ).coerceIn(0, 255) / 255.0
            }
        } catch (_: Exception) {
            0.5
        }
    }
}
