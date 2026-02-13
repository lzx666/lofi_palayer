import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audio_service/audio_service.dart';

// 1. 定义后台音频处理器：负责管理隐藏的 WebView 和系统媒体状态
class MyAudioHandler extends BaseAudioHandler {
  HeadlessInAppWebView? _webEngine;
  double _volume = 0.3;

  MyAudioHandler() {
    _initWebView();
  }

  void _initWebView() {
    _webEngine = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri("https://live.bilibili.com/27519423")),
      initialSettings: InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false, // 允许自动播放
        javaScriptEnabled: true,
        domStorageEnabled: true,
        // 伪装 PC 端 User-Agent 以获取最佳兼容性
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      ),
      onLoadStop: (controller, url) async {
        // 模仿原项目的轮询脚本，确保找到 video 标签并取消静音
        await controller.evaluateJavascript(source: """
          const pollVideo = setInterval(() => {
            const v = document.querySelector('video');
            if (v) {
              v.muted = false;
              v.volume = $_volume;
              v.play().then(() => {
                console.log('Audio Playing');
                clearInterval(pollVideo);
              });
            }
          }, 1500);
        """);
      },
    );
    _webEngine?.run();

    // 设置通知栏显示的媒体信息
    mediaItem.add(const MediaItem(
      id: 'lofi_bilibili_stream',
      album: 'Lofi Girl',
      title: 'Lofi Radio Live',
      artist: 'Bilibili Stream',
    ));
  }

  @override
  Future<void> play() async {
    await _webEngine?.webViewController?.evaluateJavascript(source: "document.querySelector('video').play();");
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      controls: [MediaControl.pause],
      systemActions: {MediaAction.pause},
    ));
  }

  @override
  Future<void> pause() async {
    await _webEngine?.webViewController?.evaluateJavascript(source: "document.querySelector('video').pause();");
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      controls: [MediaControl.play],
      systemActions: {MediaAction.play},
    ));
  }

  void updateVolume(double val) {
    _volume = val;
    _webEngine?.webViewController?.evaluateJavascript(source: "document.querySelector('video').volume = $val;");
  }
}

// 全局变量以便 Provider 调用
late MyAudioHandler _handler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化音频服务，这会让 App 在后台时被识别为播放器
  _handler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.lofi.radio.audio',
      androidNotificationChannelName: 'Lofi Music Service',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => LofiProvider()..init(),
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: LofiHomePage(),
      ),
    ),
  );
}

// --- 逻辑层 ---
class LofiProvider extends ChangeNotifier {
  bool get isPlaying => _handler.playbackState.value.playing;
  int _focusMinutes = 0;
  double _volume = 0.3;
  Timer? _timer;

  int get focusMinutes => _focusMinutes;
  double get volume => _volume;

  void init() async {
    await _loadData();
    // 监听后台状态同步给 UI
    _handler.playbackState.listen((_) => notifyListeners());
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _focusMinutes = prefs.getInt('focus_minutes') ?? 0;
    notifyListeners();
  }

  void togglePlay() {
    if (isPlaying) {
      _handler.pause();
      _timer?.cancel();
    } else {
      _handler.play();
      _startTimer();
    }
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (t) {
      _focusMinutes++;
      _saveData();
      notifyListeners();
    });
  }

  void _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('focus_minutes', _focusMinutes);
  }

  void setVolume(double val) {
    _volume = val;
    _handler.updateVolume(val);
    notifyListeners();
  }
}

// --- UI 层 ---
class LofiHomePage extends StatelessWidget {
  const LofiHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final lofi = Provider.of<LofiProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            VinylDisc(isPlaying: lofi.isPlaying),
            const SizedBox(height: 40),
            const Text("Lofi Radio Player", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            Text("Focus: ${lofi.focusMinutes} min", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 40),
            IconButton(
              iconSize: 80,
              icon: Icon(lofi.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white),
              onPressed: () => lofi.togglePlay(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Slider(
                value: lofi.volume,
                onChanged: (v) => lofi.setVolume(v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VinylDisc extends StatefulWidget {
  final bool isPlaying;
  const VinylDisc({super.key, required this.isPlaying});
  @override
  State<VinylDisc> createState() => _VinylDiscState();
}

class _VinylDiscState extends State<VinylDisc> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 12));
    if (widget.isPlaying) _controller.repeat();
  }
  @override
  void didUpdateWidget(VinylDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.isPlaying ? _controller.repeat() : _controller.stop();
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Container(
        width: 220, height: 220,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: [Colors.black, Color(0xFF222222)]),
          border: Border.all(color: Colors.white10, width: 8),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20)],
        ),
        child: const Center(child: Icon(Icons.music_note, color: Colors.white12, size: 60)),
      ),
    );
  }
}