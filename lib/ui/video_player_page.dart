import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../models/models.dart';
import '../network/api_client.dart';
import '../session.dart';
import 'tv.dart';

/// 视频在线播放页（全屏沉浸式）
///
/// - 进入：GET /open/video/play 拿各清晰度地址（直接选最高档），GET /open/video/history 续播
/// - 退出/暂停：POST /open/video/history 上报进度
/// - 横竖屏：进入即横屏且默认锁定（双横屏，竖屏进不来）；右下角方向锁
///   按钮：解锁后完全跟随手机物理方向（竖过来 = 竖屏播放），再点 = 固定
///   当前方向（横屏锁横屏、竖屏锁竖屏）；退出时恢复跟随系统
/// - 手势（整屏生效，含视频外黑边区域）：屏幕左半边上下滑调亮度（最低 10%），
///   右半边上下滑调音量（可到静音），均 2% 步进、上滑调大；左右滑（任意
///   位置）快退/快进（5s 一档，单次手势累计最多 5 分钟）
/// - 遥控器（电视，Tv.isTv；同一 APK 手机/电视双端，触摸手势全部保留）：
///   控件隐藏时页面根持焦点——左/右 = 快退/快进 10s 一档（复用 seek 手势
///   指示器与播放态冻结逻辑），OK = 唤出控件并把焦点交给播放/暂停按钮，
///   返回键不吞（系统默认退出页面）。控件可见时各按钮按方向键遍历聚焦、
///   OK 激活，进度条聚焦加粗+光晕且左右 = ±5s；2 秒自动隐藏触发时焦点
///   退回页面根
/// - 屏幕常亮：播放期间保持常亮（原生 FLAG_KEEP_SCREEN_ON），暂停时解除
///   （系统超时后可正常熄屏省电），退出播放页时恢复
/// - 覆盖控件：右上倍速菜单（仅手机：入口图标透明不可见、点击区域唤出；
///   电视不显示）；底部一行 = 播放/暂停（左）· 细进度条（与按钮同
///   中心线）· 方向锁（右下，电视隐藏，行尾留 24 余量），2 秒无操作
///   自动隐藏。
///   无返回按钮（用户要求移除），退出走系统返回手势/返回键。
///   点按：屏幕中心（±20% 屏宽/高）= 播放/暂停，其余区域 = 切换控件显示
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.item});

  final FileItem item;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

/// 屏幕手势类型
enum _GestureKind { volume, brightness, seek }

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  final _client = Session.instance.client;

  VideoPlayerController? _controller;
  String? _error;

  List<PlayUrlItem> _urls = [];
  PlayUrlItem? _current;

  double _speed = 1.0;

  /// 倍速档位（右上角菜单选择；原右半屏横滑调倍速手势已移除）
  static const List<double> _speedOptions = [1.0, 1.5, 3.0, 5.0];

  bool _controlsVisible = true;
  Timer? _hideTimer;
  int _resumeSec = 0;

  /// 对外呈现的播放态：播放按钮/播放暂停切换统一读它，不直接读底层
  /// isPlaying——底层 buffering（seek 后/加载中/网络波动）会短暂上报
  /// false，须延迟确认（_pauseConfirm）后才置 false；用户点按钮则
  /// 立即切换。暂停期间控件常驻显示
  bool _wasPlaying = true;

  /// 正在点按/拖动进度条或整屏横滑 seek。底层 seek 后会短暂 buffering
  /// （isPlaying=false，网络流上可持续约 1 秒），此间播放态冻结为
  /// 调整前的值，避免播放按钮闪成暂停态、常亮被误解除；
  /// 底层恢复播放（_onTick 检测到）或 4 秒兜底计时后解除
  bool _scrubbing = false;

  /// 进度条拖动进行中：seek 手势活跃期间不解除冻结
  bool _barDrag = false;
  Timer? _scrubTimer;

  /// 有 seek 手势正在进行（进度条拖动或整屏横滑）
  bool get _scrubGestureActive =>
      _barDrag || _gestureKind == _GestureKind.seek;

  /// "待确认暂停"进行中（已armed计时，避免每个 false tick 反复重启计时，
  /// 否则底层周期 tick 会让确认永远走不完）
  bool _pausePending = false;

  /// 底层真正开始播放过（见过 isPlaying=true）。play() 返回≠已起播，
  /// 起播前的 buffering 不参与暂停确认（此时视频即将播放，按钮应保持
  /// 播放态，否则起播慢于 1.2 秒会闪一下暂停态）
  bool _everPlayed = false;

  /// 视频可挂载显示（首帧已渲染）：Texture 在此电视上首帧前显示白色
  /// 而非黑色（录屏实测挂载后满屏白 0.4 秒，用户反馈"打开文件闪白屏"），
  /// 故等 _everPlayed（底层起播=首帧已出）再显示；800ms 兜底防起播异常
  /// 时永远黑屏
  bool _videoReady = false;
  Timer? _videoReadyTimer;

  /// "待确认暂停"计时：isPlaying=false 多为 buffering（seek 后/加载中/
  /// 网络波动，通常 1 秒内恢复），延迟确认，期间按钮保持播放态
  Timer? _pauseConfirm;

  /// 右下角方向锁：默认锁定（进入时强制双横屏）；解锁后完全跟随传感器
  /// （手机竖过来 = 竖屏播放）；再点锁定 = 固定当前方向（横锁横、竖锁竖）
  bool _orientationLocked = true;

  // 音量/亮度/快进快退手势（音量亮度走 channel: ghost/player，原生侧 MainActivity）
  static const MethodChannel _device = MethodChannel('ghost/player');
  double _volume = 0.5;
  double _brightness = 0.5;
  _GestureKind? _gestureKind; // 非空 = 手势指示器显示中
  double _gestureValue = 0; // 指示器当前值（音量/亮度 0..1，seek 为秒）
  double _gestureTarget = 0; // 连续累计值（2% 量化前）
  double _dragAccum = 0; // 横向手势累计位移
  int _seekStartMs = 0; // seek 手势起始播放位置
  int _seekSteps = 0; // seek 手势累计步数（每步 5s，单次手势最多 ±60 步 = 5 分钟）
  Timer? _gestureTimer;

  /// 遥控器（电视 D-pad）焦点节点：页面根（控件隐藏态收键）、底部播放/
  /// 暂停按钮（根态 OK 交出焦点）、进度条（聚焦时左右 = ±5s）
  final FocusNode _rootFocus = FocusNode(debugLabel: 'player-root');
  final FocusNode _playFocus = FocusNode(debugLabel: 'play-pause');
  final FocusNode _barFocus = FocusNode(debugLabel: 'progress-bar');

  /// 倍速菜单打开中：期间不触发控件自动隐藏（焦点在菜单里，控件藏掉后
  /// 菜单关闭时焦点将无处可回）
  bool _menuOpen = false;

  /// 遥控器 seek 会话：指示器显示期间（800ms 内连按/长按）从同一位置
  /// 累计，避免底层 seek 未落地时从过期 position 重复起跳（与整屏横滑
  /// 的 _seekStartMs/_seekSteps 同思路）
  int _keySeekFromMs = 0;
  int _keySeekSec = 0;

  @override
  void initState() {
    super.initState();
    // 全屏沉浸：隐藏状态栏/导航栏，退出时恢复
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // 强制传感器双横屏（竖屏进不来，左右横屏随传感器翻转），退出时恢复
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _load();
    _readDeviceValues();
    // 进入播放页即保持屏幕常亮（含加载阶段），暂停时解除
    _invokeDevice('keepScreenOn', true);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _gestureTimer?.cancel();
    _scrubTimer?.cancel();
    _pauseConfirm?.cancel();
    _videoReadyTimer?.cancel();
    _reportAndClose();
    _controller?.dispose();
    _rootFocus.dispose();
    _playFocus.dispose();
    _barFocus.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // 退出播放页解除屏幕常亮
    _invokeDevice('keepScreenOn', false);
    // 退出播放页恢复跟随系统亮度
    _invokeDevice('resetBrightness');
    // 退出播放页恢复跟随系统方向（解除方向锁）
    _invokeDevice('resetOrientation');
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (widget.item.pickCode.isEmpty) {
        throw ApiException(-1, '提取码为空（文件列表未返回 pick_code），无法获取播放地址');
      }
      debugPrint('[play] play: pickCode=${widget.item.pickCode} name=${widget.item.name}');
      final j = await _client.videoPlay(widget.item.pickCode);
      debugPrint('[play] play api ok: ${j.keys.toList()}');
      final info = parsePlayInfo(j);
      debugPrint('[play] play urls=${info.videoUrl.length} defs=${info.definitions}');
      if (info.videoUrl.isEmpty) {
        throw StateError('该视频暂未完成转码，暂时无法播放');
      }
      _urls = info.videoUrl;
      // 清晰度直接取最高档：parsePlayInfo 已按 definition 降序排序；
      // 首档初始化失败时 _initController 会自动降级到下一档
      _current = _urls.first;
      _tried..clear()..add(_current!.url);
      // 续播进度（失败忽略）
      _resumeSec = await _client.videoHistory(widget.item.pickCode);
      await _initController(_current!, startAt: _resumeSec);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('Bad state: ', ''));
      }
    }
  }

  Future<void> _initController(PlayUrlItem item, {int startAt = 0}) async {
    final old = _controller;
    final url = item.url;
    // 115 的播放地址是 /m3u8/<hash> 形式，没有 .m3u8 扩展名。
    // video_player 插件按扩展名推断流格式，识别不出就按渐进式媒体
    // （MP4 等）解析 m3u8 文本 → ExoPlaybackException: Source error。
    // 故对含 m3u8 的地址显式声明 HLS
    final isHls = url.toLowerCase().contains('m3u8');
    final c = VideoPlayerController.networkUrl(
      Uri.parse(url),
      formatHint: isHls ? VideoFormat.hls : null,
      httpHeaders: const {'User-Agent': Open115Client.ua},
    );
    try {
      debugPrint('[play] init url: $url');
      await c.initialize();
      debugPrint('[play] init ok, duration=${c.value.duration}');
      if (startAt > 0 && startAt < c.value.duration.inSeconds - 5) {
        await c.seekTo(Duration(seconds: startAt));
      }
      await c.setPlaybackSpeed(_speed);
      await c.play();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _controller = c);
      // 首帧兜底：起播慢于 800ms 也强制显示（避免网络极慢时一直黑屏）
      _videoReadyTimer?.cancel();
      _videoReadyTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted && !_videoReady) setState(() => _videoReady = true);
      });
      old?.dispose();
      c.addListener(_onTick);
      _scheduleHide();
    } catch (e, st) {
      debugPrint('[play] init FAIL: $e / $st');
      c.dispose();
      // 该档失败 → 自动降级到下一档（http 直链/不兼容编码时兜底）。
      // 115 的视频网关（videoplay.115.com）带 WAF 频控，连续快速
      // 请求 m3u8 会被拦截（ExoPlayer 表现为 Source error），故降级
      // 前强制间隔，避免一次失败引发请求风暴把自己打进黑名单
      final next = _nextAfter(item);
      if (next != null) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;
        debugPrint('[play] fallback to: ${next.title} ${next.url}');
        _current = next;
        await _initController(next, startAt: startAt);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final hint = await _probe(url);
      if (mounted) {
        setState(() => _error = '播放失败：$e$hint');
      }
    }
  }

  /// 返回 item 之后的下一个可用档位（循环列表）
  PlayUrlItem? _nextAfter(PlayUrlItem item) {
    final i = _urls.indexOf(item);
    if (i < 0 || _urls.length <= 1) return null;
    // 依次尝试后续档位，全部试过后停止（避免死循环）
    var tried = _tried;
    for (var k = 1; k < _urls.length; k++) {
      final cand = _urls[(i + k) % _urls.length];
      if (!tried.contains(cand.url)) {
        tried.add(cand.url);
        return cand;
      }
    }
    return null;
  }

  final Set<String> _tried = {};

  /// 对失败 URL 做 GET 探测：状态码 + Content-Type + 首包摘要（WAF拦截可见"空响应"）。
  /// 若返回的是 master playlist，会继续解析变体地址并做第二级探测，
  /// 便于区分是 master 拿不到还是 CDN 变体/分片被拦
  Future<String> _probe(String url) async {
    try {
      final res = await http
          .get(Uri.parse(url),
              headers: const {'User-Agent': Open115Client.ua})
          .timeout(const Duration(seconds: 8));
      final ct = res.headers['content-type'] ?? '?';
      final body = utf8.decode(res.bodyBytes, allowMalformed: true);
      debugPrint('[play] probe: ${res.statusCode} ct=$ct len=${res.bodyBytes.length} '
          'body600=${body.length > 600 ? body.substring(0, 600) : body}');
      final sb = StringBuffer('\nL1 (HTTP ${res.statusCode} · $ct · '
          '${res.bodyBytes.isEmpty ? '空响应(疑似WAF拦截)' : body}');
      // master playlist → 取第一个变体地址继续探测
      if (body.startsWith('#EXTM3U')) {
        final variant = _firstVariantUrl(body, url);
        if (variant != null) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          try {
            final r2 = await http
                .get(Uri.parse(variant),
                    headers: const {'User-Agent': Open115Client.ua})
                .timeout(const Duration(seconds: 8));
            final b2 = utf8.decode(r2.bodyBytes, allowMalformed: true);
            sb.write('\nL2 $variant\n  (HTTP ${r2.statusCode} · '
                '${r2.headers['content-type'] ?? '?'} · '
                '${r2.bodyBytes.isEmpty ? '空响应(疑似WAF拦截)' : b2}');
          } catch (e) {
            sb.write('\nL2 $variant\n  (探测失败: $e)');
          }
        }
      }
      return sb.toString().length > 900
          ? '${sb.toString().substring(0, 900)}…'
          : sb.toString();
    } catch (e) {
      return '\n(探测失败: $e)';
    }
  }

  /// 从 m3u8 内容解析第一个播放地址（变体或分片），处理相对路径
  String? _firstVariantUrl(String body, String baseUrl) {
    for (final line in body.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final u = Uri.tryParse(t);
      if (u == null) continue;
      return u.hasScheme ? t : Uri.parse(baseUrl).resolve(t).toString();
    }
    return null;
  }

  void _onTick() {
    if (!mounted) return;
    final raw = _controller?.value.isPlaying ?? false;
    // seek 落地、底层恢复播放：解除冻结的播放态（手势进行中不解除，
    // 拖动会连续触发 seek）
    if (_scrubbing && !_scrubGestureActive && raw) {
      _scrubTimer?.cancel();
      _scrubbing = false;
    }
    if (raw) {
      // 底层确认在播：撤销待确认的暂停
      _pauseConfirm?.cancel();
      _pausePending = false;
      _everPlayed = true;
      // 底层起播 = 首帧已渲染到 surface，此时挂载视频不会白屏
      if (!_videoReady) _videoReady = true;
      if (!_wasPlaying) {
        // 确认恢复播放（外部暂停结束，如音频焦点回来）
        _wasPlaying = true;
        _scheduleHide(); // 恢复播放：继续无操作自动隐藏
        _invokeDevice('keepScreenOn', true); // 恢复常亮
      } else if (_controlsVisible &&
          !_menuOpen &&
          !(_hideTimer?.isActive ?? false)) {
        // 补排自动隐藏：_seekByKeys/seek 手势 → _revealControls 时底层正在
        // buffering（isPlaying=false），_scheduleHide 被「未在播」短路且
        // 此后无人再排（_wasPlaying 冻结为 true，走不进上面的恢复分支），
        // 控件将永不隐藏。每个播放 tick 兜底检查，计时活跃时不重置
        _scheduleHide();
      }
    } else if (_wasPlaying && _everPlayed && !_scrubbing && !_pausePending) {
      // isPlaying=false 多为 buffering（seek 后/网络波动，通常 1 秒内
      // 恢复）：延迟确认暂停，期间播放按钮保持播放态。
      // 起播前（未 _everPlayed）与 seek 冻结中不武装确认
      _pausePending = true;
      _pauseConfirm = Timer(const Duration(milliseconds: 1200), () {
        _pausePending = false;
        if (!mounted || _scrubbing) return;
        if (_controller?.value.isPlaying ?? false) return;
        // 确认暂停：控件常驻 + 解除常亮（暂停期间允许系统超时熄屏省电）
        _wasPlaying = false;
        _hideTimer?.cancel();
        setState(() => _controlsVisible = true);
        _invokeDevice('keepScreenOn', false);
      });
    }
    setState(() {}); // 刷新进度条
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    // 暂停期间控件常驻，不安排自动隐藏
    if (!(_controller?.value.isPlaying ?? false)) return;
    _hideTimer = Timer(const Duration(seconds: 2), () {
      // 倍速菜单打开期间不隐藏：菜单关闭（选中/取消）时会重新 _revealControls
      if (_menuOpen) return;
      // 计时期间可能被外部暂停，触发时再校验一次
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _controlsVisible = false);
        // 焦点必须退回页面根：控件已从树上摘除，焦点若留在（已不存在的）
        // 按钮上，后续方向键会落在看不见的控件上
        if (Tv.isTv) _rootFocus.requestFocus();
      }
    });
  }

  /// 开始一次进度调整（点按/拖动进度条、整屏横滑）：冻结播放态
  void _beginScrub() {
    setState(() => _scrubbing = true);
    _armScrubTimer();
  }

  /// 手势结束/点按后 seek 可能仍在 buffering：等底层恢复播放
  /// （_onTick 检测）再解除冻结；4 秒兜底（暂停中 seek 不会恢复播放）
  void _armScrubTimer() {
    _scrubTimer?.cancel();
    _scrubTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_scrubGestureActive) {
        setState(() => _scrubbing = false);
      }
    });
  }

  Future<void> _readDeviceValues() async {
    try {
      final v = await _device.invokeMethod<num>('getVolume');
      final b = await _device.invokeMethod<num>('getBrightness');
      if (mounted) {
        setState(() {
          _volume = v?.toDouble() ?? _volume;
          _brightness = b?.toDouble() ?? _brightness;
        });
      }
    } catch (_) {
      // 非 Android 平台/通道异常忽略
    }
  }

  /// 原生调用（失败静默：非 Android 平台无此通道）
  void _invokeDevice(String method, [Object? arg]) {
    _device.invokeMethod(method, arg).catchError((_) {});
  }

  /// 视频左半边上下滑 = 亮度（最低 10%），右半边 = 音量（可到静音），
  /// 均为 2% 步进、上滑调大
  void _onVerticalDragStart(DragStartDetails d) {
    final w = MediaQuery.of(context).size.width;
    _gestureKind = d.localPosition.dx >= w / 2
        ? _GestureKind.volume
        : _GestureKind.brightness;
    _gestureValue = _gestureKind == _GestureKind.volume ? _volume : _brightness;
    _gestureTarget = _gestureValue;
    _gestureTimer?.cancel();
    setState(() {}); // 显示指示器
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    final kind = _gestureKind;
    if (kind == null) return;
    final h = MediaQuery.of(context).size.height;
    // 屏高 60% 的滑动覆盖全量程，上滑（dy<0）为增；结果量化到 2% 步进
    _gestureTarget -= d.delta.dy / (h * 0.6);
    final min = kind == _GestureKind.volume ? 0.0 : 0.10;
    final next =
        (((_gestureTarget / 0.02).round() * 0.02).clamp(min, 1.0)).toDouble();
    _gestureValue = next;
    setState(() {});
    if (kind == _GestureKind.volume) {
      _volume = next;
      _invokeDevice('setVolume', next);
    } else {
      _brightness = next;
      _invokeDevice('setBrightness', next);
    }
  }

  /// 横向手势（整屏任意位置）：左右滑 = 快退/快进（5s 一档、单次手势累计最多
  /// 5 分钟）。倍速原为右半屏横滑手势，已改为右上角菜单调节
  void _onHorizontalDragStart(DragStartDetails d) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    _gestureKind = _GestureKind.seek;
    _beginScrub(); // 连续 seek 期间冻结播放态，手势结束等恢复播放再解除
    _gestureValue = 0;
    _seekStartMs = c.value.position.inMilliseconds;
    _seekSteps = 0;
    _dragAccum = 0;
    _gestureTimer?.cancel();
    setState(() {}); // 显示指示器
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    if (_gestureKind != _GestureKind.seek) return;
    _dragAccum += d.delta.dx;
    // 24px 一档（与原 48px/10s 灵敏度一致），单次手势累计最多 ±60 档 = 5 分钟
    final steps = (_dragAccum / 24).truncate().clamp(-60, 60).toInt();
    if (steps == _seekSteps) return;
    _seekSteps = steps;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final durMs = c.value.duration.inMilliseconds;
    final target = (_seekStartMs + steps * 5000).clamp(0, durMs).toInt();
    c.seekTo(Duration(milliseconds: target));
    _gestureValue = (steps * 5).toDouble();
    setState(() {});
  }

  void _onGestureDragEnd() {
    // seek 手势结束：可能仍在 buffering，等恢复播放再解除冻结
    if (_scrubbing) _armScrubTimer();
    _gestureTimer?.cancel();
    _gestureTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _gestureKind = null);
    });
  }

  // ---- 遥控器（电视 D-pad，参考 VLC on Android TV 的模型）----
  // 手机上所有手势/触摸路径不变；以下逻辑仅 Tv.isTv 时生效

  /// 页面根（控件隐藏态）的遥控器按键：左/右 = ±10s seek（复用触摸手势的
  /// 指示器与播放态冻结逻辑），OK = 唤出控件并把焦点交给播放/暂停按钮
  /// （不直接播放/暂停，避免连按 OK 状态抖动）；上/下不响应。
  /// 焦点在具体按钮上时不在根节点、此回调不命中，交给默认遍历/激活；
  /// 返回键不吞（系统默认退出页面）
  KeyEventResult _onRootKeyEvent(FocusNode node, KeyEvent event) {
    if (!Tv.isTv || !node.hasPrimaryFocus || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _seekByKeys(-10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _seekByKeys(10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || // 遥控器 OK（DPAD_CENTER）
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _revealControls();
      _focusPlayButton();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 遥控器 seek：sec 为单档秒数（根态 ±10s、进度条聚焦态 ±5s），走触摸
  /// seek 同一套冻结（_beginScrub/_armScrubTimer）与指示器逻辑
  void _seekByKeys(int sec) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_gestureKind != _GestureKind.seek) {
      // 新会话从当前播放位置起跳；指示器仍显示中（800ms 内连按/长按）
      // 则继续累计
      _keySeekFromMs = c.value.position.inMilliseconds;
      _keySeekSec = 0;
    }
    _keySeekSec += sec;
    final durMs = c.value.duration.inMilliseconds;
    final target =
        (_keySeekFromMs + _keySeekSec * 1000).clamp(0, durMs).toInt();
    c.seekTo(Duration(milliseconds: target));
    _beginScrub();
    _flashGesture(_GestureKind.seek, _keySeekSec.toDouble());
    _revealControls();
  }

  /// 遥控器按键触发手势指示器：显示数值，800ms 无后续按键后消失
  /// （与拖动结束的消失节奏一致）
  void _flashGesture(_GestureKind kind, double value) {
    _gestureKind = kind;
    _gestureValue = value;
    _gestureTimer?.cancel();
    _gestureTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _gestureKind = null);
    });
    setState(() {});
  }

  /// 根态 OK 后把焦点交给底部播放/暂停按钮：控件可能刚被唤出（按钮尚未
  /// 挂载），等一帧挂载完成后再要焦点
  void _focusPlayButton() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _playFocus.context != null) _playFocus.requestFocus();
    });
  }

  /// 右下角方向锁切换：锁定 = 原生固定当前方向（横屏锁横屏、竖屏锁竖屏，
  /// 传感器失效）；解锁 = 恢复完全跟随系统传感器（手机竖过来变竖屏播放）。
  /// UNSPECIFIED 必须走原生重置：SystemChrome 传全方向会被引擎映射成
  /// SENSOR_LANDSCAPE/SENSOR_PORTRAIT，不是真正的"跟随系统"
  void _toggleOrientationLock() {
    setState(() => _orientationLocked = !_orientationLocked);
    if (_orientationLocked) {
      _invokeDevice('lockCurrentOrientation');
    } else {
      _invokeDevice('resetOrientation');
    }
    _revealControls();
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null) return;
    if (_wasPlaying) {
      // 用户主动暂停：立即切换（不等延迟确认），暂停侧效应同步施加
      _wasPlaying = false;
      _pauseConfirm?.cancel();
      _pausePending = false;
      _hideTimer?.cancel();
      _invokeDevice('keepScreenOn', false); // 暂停期间允许系统超时熄屏省电
      await c.pause();
      await _report(watchEnd: false);
      setState(() => _controlsVisible = true); // 暂停期间控件常驻
    } else {
      _wasPlaying = true;
      _invokeDevice('keepScreenOn', true);
      await c.play();
      setState(() => _controlsVisible = true);
      _scheduleHide();
    }
  }

  Future<void> _report({required bool watchEnd}) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final sec = c.value.position.inSeconds;
    if (sec <= 0 && !watchEnd) return;
    try {
      await _client.reportVideoHistory(widget.item.pickCode, sec,
          watchEnd: watchEnd);
    } catch (_) {/* 进度上报失败静默 */}
  }

  Future<void> _reportAndClose() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final finished = c.value.position.inSeconds >=
        c.value.duration.inSeconds - 5;
    await _report(watchEnd: finished);
  }

  @override
  Widget build(BuildContext context) {
    // 黑底页显式用浅色状态栏图标（其余浅色页为深色）
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
      backgroundColor: Colors.black,
      // opaque：整屏接收指针事件。默认 deferToChild 时，视频宽高比与屏幕
      // 不一致导致 Center/AspectRatio 外的黑边区域无子控件可命中，手势
      // （亮度/音量/快进）只对视频画面本身生效；opaque 后全屏可用。
      // 返回按钮/进度条在 hit-test 更深层，竞技场中仍优先，不受影响
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 点按仅切换控件显示/隐藏，与播放/暂停状态无关；
        // 播放中显示后 2 秒无操作自动隐藏，暂停期间不自动隐藏
        onTap: () {
          setState(() => _controlsVisible = !_controlsVisible);
          if (_controlsVisible) {
            _scheduleHide();
          } else if (Tv.isTv) {
            // 控件藏掉时焦点退回页面根，避免悬在已隐藏的按钮上
            _rootFocus.requestFocus();
          }
        },
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onHorizontalDragStart: _onHorizontalDragStart,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onVerticalDragEnd: (_) => _onGestureDragEnd(),
        onVerticalDragCancel: _onGestureDragEnd,
        onHorizontalDragEnd: (_) => _onGestureDragEnd(),
        onHorizontalDragCancel: _onGestureDragEnd,
        child: Focus(
          // 页面根焦点（电视遥控器）：控件隐藏态由它收方向/确认键（见
          // _onRootKeyEvent）；焦点在具体按钮上时不处理，交给默认遍历/
          // 激活。手机上 autofocus 无副作用：触摸不移动焦点，根节点无视觉
          focusNode: _rootFocus,
          autofocus: true,
          onKeyEvent: _onRootKeyEvent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 视频铺满全屏（Center+AspectRatio 等比居中，不裁切不溢出），
              // 横竖屏均占满整屏
              // 首帧渲染前不挂载视频（Texture 未出帧时此电视显示白色），
              // 期间黑底 + 加载圈
              if (_controller != null &&
                  _controller!.value.isInitialized &&
                  _videoReady)
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  ),
                )
              else if (_error != null)
                _errorView()
              else
                const Center(
                    child: CircularProgressIndicator(color: Colors.white)),
              if (_controlsVisible && _controller != null) _controlsLayer(),
              if (_gestureKind != null) _gestureIndicator(),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _errorView() {
    // 报错文案可能很长（含探测摘要），必须可滚动避免溢出
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off, color: Colors.white54, size: 48),
              const SizedBox(height: 12),
              Text(_error ?? '播放失败',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
              if (_current != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${_current!.title} · ${_current!.url}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              const SizedBox(height: 16),
              if (_urls.isNotEmpty)
                OutlinedButton(
                  onPressed: () {
                    setState(() => _error = null);
                    _initController(_current!, startAt: _resumeSec);
                  },
                  child: const Text('重试', style: TextStyle(color: Colors.white)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 重新显示覆盖控件并重置 2 秒隐藏计时
  void _revealControls() {
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  /// 覆盖控件层：外面再包一层不参与遍历的 Focus——控件可见期间任何按键
  /// （方向键在按钮间移动等）都重置 2 秒自动隐藏计时，避免遥控器导航
  /// 中途控件消失（参考 VLC：有按键活动时控件常驻）。进度条自身处理掉的
  /// 左右键（±5s seek）不会冒泡到这里，由 _seekByKeys 里的 _revealControls
  /// 补计时
  Widget _controlsLayer() {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: Tv.isTv
          ? (node, event) {
              if (event is! KeyUpEvent) _revealControls();
              return KeyEventResult.ignored;
            }
          : null,
      child: Stack(fit: StackFit.expand, children: _controls()),
    );
  }

  /// 覆盖控件：右上倍速（仅手机）；底部一行 = 播放/暂停（左）· 进度条（中）。
  /// 不放返回按钮（用户要求移除）：退出走系统返回手势/遥控器返回键
  List<Widget> _controls() {
    final c = _controller!;
    return [
      // 倍速入口仅手机：电视遥控器无法盲点透明入口，电视上干脆不构建
      // （也不进 D-pad 焦点遍历）
      if (!Tv.isTv)
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(child: _speedMenu()),
        ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          // 底部渐变，保证控件在亮色画面上可读
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black54],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                IconButton(
                  focusNode: _playFocus, // 电视：根态 OK 把焦点交到这里
                  // 透明按钮：无圆形底，纯三角/双竖条图标
                  iconSize: 32,
                  icon: Icon(
                    _wasPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  onPressed: _togglePlay,
                ),
                Expanded(child: _progressBar(c)),
                // 右下角方向锁仅手机：电视无重力传感器、不随物理方向
                // 翻转，锁不锁没有意义
                if (!Tv.isTv)
                  IconButton(
                    // 默认锁定（双横屏）；解锁后跟随手机物理方向
                    // （竖过来 = 竖屏播放）
                    iconSize: 22,
                    icon: Icon(
                      _orientationLocked
                          ? Icons.screen_lock_rotation
                          : Icons.screen_rotation,
                      color: _orientationLocked
                          ? Colors.white
                          : Colors.white70,
                    ),
                    tooltip: _orientationLocked ? '解锁屏幕方向' : '锁定横屏',
                    onPressed: _toggleOrientationLock,
                  ),
                // 电视：行尾没有方向锁按钮垫着，进度条会顶到屏幕右缘，
                // 补 24 余量；手机端行尾自带方向锁按钮，不加
                if (Tv.isTv) const SizedBox(width: 24),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  /// 右上角倍速菜单（仅手机构建，见 _controls）：入口图标完全透明不可见
  /// （用户要求隐藏），但右上角 48x48 点击区域仍可点出菜单调节倍速。
  /// 深色直角面板与播放器沉浸式黑底风格一致；菜单打开期间（_menuOpen）
  /// 不触发控件自动隐藏，选中/取消后重新唤出
  Widget _speedMenu() {
    return PopupMenuButton<double>(
      tooltip: '倍速',
      position: PopupMenuPosition.under,
      color: Colors.black87,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      icon: const Icon(Icons.speed, color: Colors.transparent),
      onOpened: () => _menuOpen = true,
      onSelected: (v) {
        _menuOpen = false;
        setState(() => _speed = v);
        _controller?.setPlaybackSpeed(v);
        _revealControls();
      },
      onCanceled: () {
        _menuOpen = false;
        _revealControls();
      },
      itemBuilder: (_) => [
        for (final v in _speedOptions)
          PopupMenuItem(
            value: v,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  child: v == _speed
                      ? const Icon(Icons.check, size: 18, color: Colors.white)
                      : null,
                ),
                Text(
                  _fmtSpeed(v),
                  style: TextStyle(
                    color: v == _speed ? Colors.white : Colors.white60,
                    fontWeight: v == _speed ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 速度显示：整数不带小数（1x/2x），小数保留有效位（1.5x/2.5x）
  String _fmtSpeed(double v) {
    var s = v.toStringAsFixed(2);
    if (s.contains('.')) {
      s = s
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    return '${s}x';
  }

  /// 细进度条（2px）：已播放白色，未播放半透明（浅阴影感）；
  /// 24px 触摸区与播放按钮同中心线，点按/横向拖动均跟手 seek。
  /// 电视：可聚焦，聚焦态加粗到 4px + 白色光晕（3 米距离可见），
  /// 左右键 = ±5s seek（handled 拦住，不走默认焦点遍历）
  Widget _progressBar(VideoPlayerController c) {
    final durMs = c.value.duration.inMilliseconds;
    final ratio = durMs > 0
        ? (c.value.position.inMilliseconds / durMs).clamp(0.0, 1.0).toDouble()
        : 0.0;
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      void seekTo(Offset local) {
        final r = (local.dx / w).clamp(0.0, 1.0).toDouble();
        c.seekTo(Duration(milliseconds: (r * durMs).round()));
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          // 点按 seek 后底层 buffering 可持续约 1 秒：冻结播放态，
          // 待恢复播放（_onTick 检测）或 4 秒兜底计时后解除
          _beginScrub();
          seekTo(d.localPosition);
        },
        onHorizontalDragStart: (_) {
          // 拖动期间连续 seek，底层反复进出 buffering：冻结播放态，
          // 播放按钮保持拖动前的状态（视频本来就是播着的）。
          // 同时防止 2 秒自动隐藏计时在中途把进度条藏掉
          _barDrag = true;
          _revealControls();
          _beginScrub();
        },
        onHorizontalDragUpdate: (d) => seekTo(d.localPosition),
        onHorizontalDragEnd: (_) {
          _barDrag = false;
          // 拖完 seek 可能仍在 buffering：等恢复播放再解除冻结
          _armScrubTimer();
          // 拖完恢复控件自动隐藏计时
          _scheduleHide();
        },
        onHorizontalDragCancel: () {
          _barDrag = false;
          _armScrubTimer();
        },
        // ListenableBuilder：焦点变化时重建，切换加粗/光晕视觉
        child: ListenableBuilder(
          listenable: _barFocus,
          builder: (context, _) {
            final focused = _barFocus.hasFocus;
            return Focus(
              focusNode: _barFocus,
              // 手机上不可聚焦（触摸交互不变）；电视进入 D-pad 遍历
              canRequestFocus: Tv.isTv,
              onKeyEvent: (node, event) {
                if (!Tv.isTv || event is KeyUpEvent) {
                  return KeyEventResult.ignored;
                }
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.arrowLeft) {
                  _seekByKeys(-5);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowRight) {
                  _seekByKeys(5);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: SizedBox(
                height: 24,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    height: focused ? 4 : 2,
                    width: w,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(focused ? 2 : 1),
                      // 聚焦光晕：3 米距离也要看得清焦点在哪
                      boxShadow: focused
                          ? const [
                              BoxShadow(color: Colors.white60, blurRadius: 6),
                            ]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(focused ? 2 : 1),
                      child: Container(
                        color: Colors.white38, // 底轨：半透明阴影感
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: ratio,
                          child: const ColoredBox(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    });
  }

  /// 手势指示器：居中显示图标 + 数值（音量/亮度百分比、快进快退 ±Ns），
  /// 拖动结束 800ms 后消失
  Widget _gestureIndicator() {
    final kind = _gestureKind!;
    final v = _gestureValue;
    final icon = switch (kind) {
      _GestureKind.volume => v <= 0 ? Icons.volume_off : Icons.volume_up,
      _GestureKind.brightness => Icons.brightness_6,
      _GestureKind.seek => v < 0 ? Icons.fast_rewind : Icons.fast_forward,
    };
    final label = switch (kind) {
      _GestureKind.seek => v >= 0 ? '+${v.toInt()}s' : '${v.toInt()}s',
      _ => '${(v * 100).round()}%',
    };
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
