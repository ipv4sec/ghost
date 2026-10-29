package com.moejs.ghost

import android.Manifest
import android.app.UiModeManager
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
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
// resetOrientation 解除方向锁/退出播放页时恢复"跟随系统"方向。
// 另有 isTv 供 Dart 侧电视判定（UiModeManager，见 lib/ui/tv.dart）
//
// 备份通道（channel: ghost/backup）：凭证备份文件的路径解析与存储权限，
// 见 lib/util/backup_service.dart。API<=29 用 READ/WRITE_EXTERNAL_STORAGE
// 运行时权限（+ manifest requestLegacyExternalStorage）；API 30+ 用
// MANAGE_EXTERNAL_STORAGE（「所有文件访问」设置页授权，非弹窗）。
// 注意 FlutterActivity 不是 ComponentActivity，不能 registerForActivityResult，
// 权限结果走 onRequestPermissionsResult 桥接。
class MainActivity : FlutterActivity() {
    private var initialLink: String? = null
    private var queuedLink: String? = null
    private var channel: MethodChannel? = null

    private companion object {
        const val REQ_STORAGE = 0x67
    }

    private var pendingStorageResult: MethodChannel.Result? = null

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
        setUpBackupChannel(engine)
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
                "isTv" -> result.success(isTv())
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

    /// 是否运行在电视上（Android TV / Sony 电视）：
    /// Dart 侧 lib/ui/tv.dart 的 Tv.init() 启动时读取一次
    private fun isTv(): Boolean {
        val um = getSystemService(UI_MODE_SERVICE) as UiModeManager
        return um.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
    }

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

    // ---------- ghost/backup：凭证备份的路径与存储权限 ----------

    private fun setUpBackupChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "ghost/backup").setMethodCallHandler { call, result ->
            when (call.method) {
                "externalDir" -> result.success(externalDir())
                "storageStatus" -> result.success(storageStatus())
                "requestStorage" -> requestStorage(result)
                "openAllFilesAccess" -> openAllFilesAccess(result)
                else -> result.notImplemented()
            }
        }
    }

    /// 主共享存储根目录（多用户/厂商差异由系统解析；Dart 侧另有常量兜底）
    private fun externalDir(): String = try {
        Environment.getExternalStorageDirectory().absolutePath
    } catch (_: Exception) {
        "/storage/emulated/0"
    }

    private fun runtimeGranted(): Boolean =
        checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED

    /// mode=runtime（API<=29，普通弹窗授权）/ manage（API 30+，设置页授权）
    private fun storageStatus(): Map<String, Any> =
        if (Build.VERSION.SDK_INT >= 30) mapOf(
            "sdk" to Build.VERSION.SDK_INT,
            "mode" to "manage",
            "granted" to Environment.isExternalStorageManager()
        )
        else mapOf(
            "sdk" to Build.VERSION.SDK_INT,
            "mode" to "runtime",
            "granted" to runtimeGranted()
        )

    /// API<=29：系统运行时权限弹窗（电视遥控器可操作）；API 30+ 恒 false（须走设置页）
    private fun requestStorage(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= 30 || pendingStorageResult != null) {
            result.success(false)
            return
        }
        if (runtimeGranted()) {
            result.success(true)
            return
        }
        pendingStorageResult = result
        requestPermissions(
            arrayOf(
                Manifest.permission.READ_EXTERNAL_STORAGE,
                Manifest.permission.WRITE_EXTERNAL_STORAGE
            ),
            REQ_STORAGE
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        // super 不可省：引擎的插件权限回调转发依赖它
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_STORAGE) {
            val ok = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingStorageResult?.success(ok)
            pendingStorageResult = null
        }
    }

    /// API 30+：跳「所有文件访问」授权页；电视/定制 ROM 无该页时逐级降级。
    /// 返回的是"设置页是否打开"，实际授予态由 Dart 在 resumed 后重查 storageStatus
    private fun openAllFilesAccess(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 30) {
            result.success(runtimeGranted())
            return
        }
        val pkgUri = Uri.fromParts("package", packageName, null)
        val ok = try {
            startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, pkgUri))
            true
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                true
            } catch (_: Exception) {
                try {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkgUri))
                } catch (_: Exception) {
                    // 彻底无设置页可跳
                }
                false // 应用详情页无法授予"所有文件访问"，按未解决处理
            }
        }
        result.success(ok)
    }
}
