import 'dart:async';
// 删除了冗余的 dart:ui 导入
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LofiProvider()..init()),
      ],
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: LofiHomePage(),
      ),
    ),
  );
}

// --- 逻辑层 ---
class LofiProvider extends ChangeNotifier {
  bool _isPlaying = false;
  int _focusMinutes = 0;
  double _volume = 0.3;
  HeadlessInAppWebView? _webEngine;
  Timer? _timer;

  bool get isPlaying => _isPlaying;
  int get focusMinutes => _focusMinutes;
  double get volume => _volume;

  void init() async {
    await _loadData();
    _setupAudioEngine();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _focusMinutes = prefs.getInt('focus_minutes') ?? 0;
    String lastDate = prefs.getString('last_date') ?? "";
    String today = DateTime.now().toString().substring(0, 10);

    if (lastDate != today) {
      _focusMinutes = 0;
      await prefs.setString('last_date', today);
    }
    notifyListeners();
  }

  void _setupAudioEngine() {
    _webEngine = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri("https://live.bilibili.com/27519423")),
      initialSettings: InAppWebViewSettings(
        // 移除了报错的 allowsBackgroundMediaPlayback 参数
        mediaPlaybackRequiresUserGesture: false, 
      ),
      onLoadStop: (controller, url) async {
        await controller.evaluateJavascript(source: """
          const v = document.querySelector('video');
          if (v) {
            v.muted = false;
            v.volume = $_volume;
          }
        """);
      },
    );
    _webEngine?.run();
  }

  void togglePlay() {
    _isPlaying = !_isPlaying;
    _webEngine?.webViewController?.evaluateJavascript(
      source: _isPlaying ? "document.querySelector('video').play();" : "document.querySelector('video').pause();"
    );

    if (_isPlaying) {
      _startTimer();
    } else {
      _stopTimer();
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

  void _stopTimer() => _timer?.cancel();

  void _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('focus_minutes', _focusMinutes);
  }

  void setVolume(double val) {
    _volume = val;
    _webEngine?.webViewController?.evaluateJavascript(
      source: "document.querySelector('video').volume = $val;"
    );
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
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1E1E2C), Color(0xFF0F0F1E)],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  VinylDisc(isPlaying: lofi.isPlaying),
                  const SizedBox(height: 40),
                  const Text(
                    "Lofi Radio Player",
                    style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Today Focus: ${lofi.focusMinutes} min",
                    // 修复：使用 withValues 代替被弃用的 withOpacity
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16),
                  ),
                  const SizedBox(height: 60),
                  GestureDetector(
                    onTap: () => lofi.togglePlay(),
                    child: Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // 修复：使用 withValues
                        color: Colors.white.withValues(alpha: 0.1),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Icon(
                        lofi.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white, size: 48,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: 250,
                    child: Slider(
                      value: lofi.volume,
                      activeColor: Colors.deepPurpleAccent,
                      onChanged: (v) => lofi.setVolume(v),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
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
        width: 240, height: 240,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              // 修复：使用 withValues
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 30,
              spreadRadius: 5,
            )
          ],
          gradient: const SweepGradient(
            colors: [Colors.black, Color(0xFF222222), Colors.black],
            stops: [0.0, 0.5, 1.0],
          ),
          border: Border.all(color: Colors.white10, width: 8),
        ),
        child: Center(
          child: Container(
            width: 60, height: 60,
            decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
            child: const Icon(Icons.music_note, color: Colors.white24, size: 30),
          ),
        ),
      ),
    );
  }
}