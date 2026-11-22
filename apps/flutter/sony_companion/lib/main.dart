// Sony Companion — Flutter interface for Android and Windows.
//
// Shares the Rust engine with the macOS and iOS apps. The visual language is
// the same: a content layer on system surfaces, and a functional layer of
// translucent panels and a floating status capsule.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'engine.dart';

void main() {
  runApp(const SonyCompanionApp());
}

// MARK: - Design tokens

const List<(int, String)> quickAccessOptions = [
  (0, 'No function'), (1, 'NC/ASM off'), (2, 'NC/ASM'), (3, 'NC off'),
  (4, 'Ambient off'), (16, 'Quick Attention'), (17, 'NC optimizer'),
  (32, 'Play/Pause'), (33, 'Next track'), (34, 'Previous track'),
  (35, 'Volume up'), (36, 'Volume down'), (48, 'Voice recognition'),
  (49, 'Notifications'), (50, 'Google Assistant'), (55, 'Amazon Alexa'),
  (54, 'Quick Access'), (67, 'Quick Access 1'), (68, 'Quick Access 2'),
  (80, 'NC/NCSS/ASM off'), (81, 'NC/NCSS/ASM'), (82, 'NC/NCSS off'),
  (83, 'NCSS/ASM off'), (84, 'NC/NCSS'), (85, 'NCSS/ASM'), (86, 'NCSS off'),
  (87, 'Ambient setting'), (88, 'Standard voice'), (89, 'Listening mode'),
  (112, 'Mic mute'), (113, 'Game up'), (114, 'Chat up'),
];

class Tokens {
  static const accent = Color(0xFF0088FF);
  static const surfaceDark = Color(0xFF1C1C1E);
  static const surfaceLight = Color(0xFFF2F2F7);
  static const cardRadius = 18.0;
  static const heroRadius = 26.0;
}

// MARK: - State

class SonyState extends ChangeNotifier {
  SonyState() {
    _transport.setHandler(_onBytes);
    _transport.setPermissionHandler(refreshDevices);
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    if (preview) {
      status = const {
        'state': 'Ready',
        'model': 'WH-1000XM6',
        'firmware': '3.1.5',
        'battery': 72,
        'charging': 0,
        'nc': {'enabled': 1, 'mode': 1, 'ambient_mode': 0, 'level': 8},
        'eq': {
          'enabled': 1,
          'preset': 160,
          'band_count': 10,
          'band_step': 13,
          'clear_bass': 2,
          'clear_bass_min': -10,
          'clear_bass_max': 10,
          'preset_name': 'Custom',
          'bands': [11, 10, 9, 6, 5, 8, 9, 8, 10, 11],
          'presets': [
            {'id': 0, 'name': 'Off'},
            {'id': 32, 'name': 'Gaming'},
            {'id': 48, 'name': 'Heavy'},
            {'id': 49, 'name': 'Clear'},
            {'id': 50, 'name': 'Hard'},
            {'id': 51, 'name': 'Soft'},
            {'id': 160, 'name': 'Custom'},
            {'id': 161, 'name': 'User 1'},
            {'id': 162, 'name': 'User 2'},
          ],
        },
        'pending_write': 0,
        'revision': 5,
      };
      connected = true;
      log = ['design preview — not live device data'];
    }
  }

  final _transport = SonyTransport();
  late final Timer _ticker;

  /// Design-review data. Only active when built with
  /// `--dart-define=SONY_UI_PREVIEW=true`; never in a normal run.
  static const bool preview = bool.fromEnvironment('SONY_UI_PREVIEW');

  MdrEngine? _engine;
  Map<String, dynamic> status = const {};
  List<String> log = [];
  String? error;
  bool connected = false;

  String engineVersion = '';
  String transportNote = '';

  List<String> devices = const [];

  bool get isReady => status['state'] == 'Ready';

  Future<void> refreshDevices() async {
    try {
      devices = await _transport.listDevices();
      transportNote = '';
    } on PlatformException catch (e) {
      transportNote = e.message ?? 'Transport unavailable on this build.';
    } on MissingPluginException {
      transportNote = 'Transport is not implemented on this platform yet.';
    }
    notifyListeners();
  }

  Future<void> connectTo(String device) async {
    disconnect();
    try {
      final engine = MdrEngine.create();
      engineVersion = engine.version;
      _engine = engine;
      await _transport.open(device);
      final first = engine.connect(_nowMs());
      if (first != null) await _transport.write(first);
      connected = true;
      error = null;
      _record('engine $engineVersion · $device');
      _publish();
    } catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  void disconnect() {
    _engine?.dispose();
    _engine = null;
    _transport.close();
    connected = false;
    status = const {};
    notifyListeners();
  }

  Future<void> _onBytes(Uint8List data) async {
    final engine = _engine;
    if (engine == null) return;
    final follow = engine.receive(data, _nowMs());
    _publish();
    if (follow != null) {
      await _transport.write(follow);
    }
  }

  void _tick() {
    final engine = _engine;
    if (engine == null) return;
    final retry = engine.poll(_nowMs());
    if (retry != null) _transport.write(retry);
    _publish();
  }

  void setNoise({required bool enabled, required int mode, required int level}) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setNoiseControl(
      enabled: enabled,
      mode: mode,
      ambientMode: 0,
      level: level,
      nowMs: _nowMs(),
    );
    if (bytes != null) _transport.write(bytes);
    _record('→ NCASM_SET_PARAM');
  }

  void setPreset(int preset) {
    final engine = _engine;
    if (engine == null) return;
    final eq = status['eq'] as Map<String, dynamic>?;
    final custom = preset == 0xA0 || (preset >= 0xA1 && preset <= 0xA5);
    final bands = custom
        ? ((eq?['bands'] as List?)?.cast<int>() ?? const <int>[])
        : const <int>[];
    final bytes = engine.setEqualizerPreset(
      preset: preset,
      bands: bands,
      nowMs: _nowMs(),
    );
    if (bytes != null) _transport.write(bytes);
    _record('→ EQEBB_SET_PARAM $preset');
  }

  void setPlaybackControl(int control) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setPlaybackControl(control, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ PLAY_SET_STATUS $control');
  }

  void setMusicVolume(int volume) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setMusicVolume(volume, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ PLAY_SET_PARAM music volume $volume');
  }

  void setCallVolume(int volume) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setCallVolume(volume, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ PLAY_SET_PARAM call volume $volume');
  }

  void setControlByWearing(bool enabled) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setControlByWearing(enabled, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ SYSTEM_SET_PARAM control by wearing ${enabled ? "on" : "off"}');
  }

  void setAdaptiveControl(bool start) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setAdaptiveControl(start, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ SENSE_SET_STATUS adaptive ${start ? "start" : "stop"}');
  }

  void setQuickAccessFunctions(List<int> functions) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setQuickAccessFunctions(functions, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ QUICK_ACCESS_EASY_SETTING ${functions.map((f) => f.toRadixString(16)).join(' ')}');
  }

  void setMicOnOff(bool enabled) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setMicOnOff(enabled, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ SYSTEM_SET_PARAM mic ${enabled ? "on" : "off"}');
  }

  void setSonyVoiceAssistant(bool enabled) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setSonyVoiceAssistant(enabled, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ SYSTEM_SET_PARAM Sony VA ${enabled ? "on" : "off"}');
  }

  void setVoiceGuidance(bool enabled) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setVoiceGuidance(enabled, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ VOICE_GUIDANCE_SET_PARAM ${enabled ? "on" : "off"}');
  }

  void setVoiceGuidanceVolume(int volume) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setVoiceGuidanceVolume(volume, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ VOICE_GUIDANCE_SET_PARAM volume $volume');
  }

  void setSafeVolume(int level) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setSafeVolume(level, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ SAFE_LISTENING_SET_STATUS safe volume $level');
  }

  void setHeadGesture(bool enabled) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setHeadGesture(enabled, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ SYSTEM_SET_STATUS head gesture $enabled');
  }

  void powerOff() {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.powerOff(_nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ POWER_SET_STATUS user power off');
  }

  void setSmartTalking(bool enabled) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setSmartTalking(enabled, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ SYSTEM_SET_PARAM speak-to-chat $enabled');
  }

  void setSmartTalkingDetail(int sensitivity, int modeOut) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setSmartTalkingDetail(sensitivity, modeOut, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ SYSTEM_SET_EXT_PARAM speak-to-chat $sensitivity/$modeOut');
  }

  void setAutoStandby(bool enabled) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setAutoStandby(enabled, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ POWER_SET_PARAM auto standby $enabled');
  }

  void setMusicHandOver(bool enabled) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setMusicHandOver(enabled, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ PERI_SET_PARAM music hand-over $enabled');
  }

  void connectPairedDevice(int index) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.connectPairedDevice(index, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ PERI_SET_EX_PARAM connect #$index');
  }

  void disconnectPairedDevice(int index) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.disconnectPairedDevice(index, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ PERI_SET_EX_PARAM disconnect #$index');
  }

  void setPairingMode(bool pairing) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setPairingMode(pairing, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ PERI_SET_STATUS pairing mode $pairing');
  }

  void setListeningMode(int mode) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setListeningMode(mode, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ AUDIO_SET_PARAM listening mode $mode');
  }

  void setGeneralSetting(int gsType, bool enabled) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setGeneralSetting(gsType, enabled, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ GENERAL_SETTING_SET_PARAM $gsType');
  }

  void setVoiceAssistant(int value) {
    final engine = _engine;
    if (engine == null) return;
    final bytes = engine.setVoiceAssistant(value, _nowMs());
    if (bytes != null) _transport.write(bytes);
    _record('→ SYSTEM_SET_PARAM voice assistant $value');
  }

  void _publish() {
    final engine = _engine;
    if (engine == null) return;
    final snap = engine.snapshot();
    if (snap.isNotEmpty) status = snap;
    notifyListeners();
  }

  void _record(String line) {
    log = [...log, line].take(200).toList();
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  @override
  void dispose() {
    _ticker.cancel();
    _engine?.dispose();
    super.dispose();
  }
}

/// Platform channel to the native Bluetooth transport.
///
/// Android and Windows both expose RFCOMM with Sony's V2 service UUID, so the
/// same protocol runs over each platform's own socket API.
class SonyTransport {
  static const _channel = MethodChannel('dev.connect.sony/transport');
  void Function(Uint8List)? _handler;

  void Function()? _onPermission;

  void setHandler(void Function(Uint8List) handler) {
    _handler = handler;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'bytes') {
        _handler?.call(call.arguments as Uint8List);
      } else if (call.method == 'permission') {
        _onPermission?.call();
      }
      return null;
    });
  }

  void setPermissionHandler(void Function() handler) {
    _onPermission = handler;
  }

  Future<List<String>> listDevices() async {
    final list = await _channel.invokeMethod<List<Object?>>('listDevices') ?? const [];
    return list.map((e) => e.toString()).toList();
  }

  Future<void> open(String device) => _channel.invokeMethod('open', {'device': device});
  Future<void> write(Uint8List bytes) => _channel.invokeMethod('write', {'bytes': bytes});
  Future<void> close() => _channel.invokeMethod('close');
}

// MARK: - Root

class SonyCompanionApp extends StatelessWidget {
  const SonyCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sony Companion',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const RootScreen(),
    );
  }

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: Tokens.accent,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF0E0E10) : const Color(0xFFF7F7FA),
      useMaterial3: true,
      fontFamily: '.AppleSystemUIFont',
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? Tokens.surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.cardRadius)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});
  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final _state = SonyState();
  String? _device;

  @override
  void initState() {
    super.initState();
    _state.addListener(_repaint);
    if (SonyState.preview) {
      _device = 'WH-1000XM6';
    } else {
      _state.refreshDevices();
    }
  }

  void _repaint() => setState(() {});

  @override
  void dispose() {
    _state.removeListener(_repaint);
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _device == null ? _picker(context) : _detail(context),
      ),
    );
  }

  Widget _picker(BuildContext context) {
    final theme = Theme.of(context);
    if (_state.transportNote.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.headphones, size: 52, color: theme.colorScheme.secondary),
              const SizedBox(height: 16),
              Text('No headphone link',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                _state.transportNote,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => _state.refreshDevices(),
                child: const Text('Check Again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_state.devices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.headphones, size: 52, color: theme.colorScheme.secondary),
              const SizedBox(height: 16),
              Text('No paired headphones',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                'Pair your Sony headphones in the system Bluetooth settings, then check again.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => _state.refreshDevices(),
                child: const Text('Check Again'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 12),
          child: Text('Headphones',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        ),
        for (final d in _state.devices)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.headphones),
              title: Text(d),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                setState(() => _device = d);
                await _state.connectTo(d);
              },
            ),
          ),
      ],
    );
  }

  Widget _detail(BuildContext context) {
    final status = _state.status;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        HeroPanel(status: status, device: _device ?? ''),
        const SizedBox(height: 16),
        if (_state.error != null) ErrorBanner(message: _state.error!),
        BatteryCard(status: status),
        const SizedBox(height: 12),
        NoiseCard(state: _state, status: status),
        const SizedBox(height: 12),
        SmartTalkingCard(state: _state, status: status),
        const SizedBox(height: 12),
        HeadGestureCard(state: _state, status: status),
        const SizedBox(height: 12),
        PlaybackCard(state: _state, status: status),
        const SizedBox(height: 12),
        VolumeCard(state: _state, status: status),
        const SizedBox(height: 12),
        Table2StatusCard(state: _state, status: status),
        const SizedBox(height: 12),
        ListeningModeCard(state: _state, status: status),
        const SizedBox(height: 12),
        EqualizerCard(state: _state, status: status),
        const SizedBox(height: 12),
        if (isEarbudModel(status)) EarpieceFittingCard(status: status),
        const SizedBox(height: 12),
        DeviceSettingsCard(state: _state, status: status),
        const SizedBox(height: 12),
        VoiceAssistantCard(state: _state, status: status),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            _state.disconnect();
            setState(() => _device = null);
          },
          child: const Text('Disconnect'),
        ),
      ],
    );
  }
}

// MARK: - Hero

class HeroPanel extends StatefulWidget {
  const HeroPanel({super.key, required this.status, required this.device});
  final Map<String, dynamic> status;
  final String device;

  @override
  State<HeroPanel> createState() => _HeroPanelState();
}

class _HeroPanelState extends State<HeroPanel> {
  Offset _pointer = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final model = (widget.status['model'] as String?)?.isNotEmpty == true
        ? widget.status['model'] as String
        : widget.device;
    final firmware = widget.status['firmware'] as String? ?? '';
    final state = widget.status['state'] as String? ?? 'Connecting';

    return MouseRegion(
      onHover: (event) => setState(() {
        final size = context.size ?? const Size(1, 1);
        _pointer = Offset(
          (event.localPosition.dx / math.max(size.width, 1)) * 2 - 1,
          (event.localPosition.dy / math.max(size.height, 1)) * 2 - 1,
        );
      }),
      onExit: (_) => setState(() => _pointer = Offset.zero),
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          final size = context.size ?? const Size(1, 1);
          _pointer = Offset(
            (d.localPosition.dx / math.max(size.width, 1)) * 2 - 1,
            (d.localPosition.dy / math.max(size.height, 1)) * 2 - 1,
          );
        }),
        onPanEnd: (_) => setState(() => _pointer = Offset.zero),
        child: Container(
          height: 190,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Tokens.heroRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Tokens.accent.withValues(alpha: 0.38),
                Tokens.accent.withValues(alpha: 0.08),
                theme.colorScheme.surface,
              ],
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: const AlwaysStoppedAnimation(0),
                  builder: (_, _) => CustomPaint(
                    painter: HeadphonePainter(
                      tilt: _pointer,
                      model: model,
                      dark: theme.brightness == Brightness.dark,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 22,
                bottom: 22,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      model.isEmpty ? widget.device : model,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        model,
                        firmware.isEmpty ? null : 'firmware $firmware',
                        (widget.status['codec'] as String?)?.isNotEmpty == true
                            ? widget.status['codec'] as String
                            : null,
                      ].whereType<String>().join(' · '),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    _GlassPill(label: state, ready: state == 'Ready'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.label, required this.ready});
  final String label;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ready ? const Color(0xFF34C759) : const Color(0xFFFF9F0A),
                ),
              ),
              const SizedBox(width: 7),
              Text(label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints the same stylised headphone as the native apps, with a parallax tilt.
class HeadphonePainter extends CustomPainter {
  HeadphonePainter({required this.tilt, required this.model, required this.dark});
  final Offset tilt;
  final String model;
  final bool dark;

  bool get _buds {
    final m = model.toUpperCase();
    return m.contains('WF-') || m.contains('BUD');
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.save();
    canvas.translate(w * 0.72, h * 0.46);

    // Parallax: a few degrees of rotation reads as depth.
    final m = Matrix4.identity()
      ..setEntry(3, 2, 0.0012)
      ..rotateY(tilt.dx * 0.18)
      ..rotateX(-tilt.dy * 0.12);
    canvas.transform(m.storage);

    if (_buds) {
      _paintBuds(canvas, size);
    } else {
      _paintOverEar(canvas, size);
    }
    canvas.restore();
  }

  void _paintOverEar(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final body = Paint()
      ..shader = ui.Gradient.linear(
        Offset(-s * 0.4, -s * 0.5),
        Offset(s * 0.4, s * 0.5),
        [
          dark ? const Color(0xFFB9B9C0) : const Color(0xFFB4B4BA),
          dark ? const Color(0xFF63636A) : const Color(0xFF6C6C74),
        ],
      );

    // Headband.
    final band = Rect.fromCircle(center: Offset(0, s * 0.06), radius: s * 0.38);
    canvas.drawArc(band, math.pi * 1.18, math.pi * 0.64, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.082
          ..strokeCap = StrokeCap.round
          ..shader = body.shader);

    // Cups.
    for (final side in [-1.0, 1.0]) {
      final center = Offset(side * s * 0.40, s * 0.16);
      final cupRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: s * 0.30, height: s * 0.56),
        Radius.circular(s * 0.15),
      );
      canvas.drawRRect(cupRect, body);
      // Accent ring on the face.
      canvas.drawCircle(
        center,
        s * 0.085,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.012
          ..color = Tokens.accent.withValues(alpha: 0.9),
      );
    }
  }

  void _paintBuds(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final body = Paint()
      ..shader = ui.Gradient.linear(
        Offset(-s * 0.3, -s * 0.4),
        Offset(s * 0.3, s * 0.4),
        [
          dark ? const Color(0xFFB9B9C0) : const Color(0xFFB4B4BA),
          dark ? const Color(0xFF63636A) : const Color(0xFF6C6C74),
        ],
      );
    for (final side in [-1.0, 1.0]) {
      final c = Offset(side * s * 0.24, -s * 0.04);
      canvas.drawCircle(c, s * 0.15, body);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: c + Offset(0, s * 0.20), width: s * 0.075, height: s * 0.26),
          Radius.circular(s * 0.04),
        ),
        body,
      );
      canvas.drawCircle(
        c + Offset(-s * 0.06, -s * 0.03),
        s * 0.045,
        Paint()..color = Tokens.accent.withValues(alpha: 0.75),
      );
    }
  }

  @override
  bool shouldRepaint(covariant HeadphonePainter old) =>
      old.tilt != tilt || old.model != model || old.dark != dark;
}

// MARK: - Cards

class _Card extends StatelessWidget {
  const _Card({required this.title, this.subtitle, required this.child});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(Tokens.cardRadius),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class BatteryCard extends StatelessWidget {
  const BatteryCard({super.key, required this.status});
  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final battery = status['battery'] as int?;
    if (battery == null) {
      return const _Card(title: 'Battery', child: Text('Not reported yet'));
    }
    return _Card(
      title: 'Battery',
      child: Row(
        children: [
          Text('$battery%',
              style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 16),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: battery / 100,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NoiseCard extends StatelessWidget {
  const NoiseCard({super.key, required this.state, required this.status});
  final SonyState state;
  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final nc = status['nc'] as Map<String, dynamic>?;
    if (nc == null) {
      return const _Card(title: 'Noise Control', child: Text('Not reported yet'));
    }
    final enabled = nc['enabled'] == 1;
    final mode = nc['mode'] as int? ?? 0;
    final selected = !enabled ? 2 : (mode == 1 ? 1 : 0);

    return _Card(
      title: 'Noise Control',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Noise Cancelling')),
              ButtonSegment(value: 1, label: Text('Ambient')),
              ButtonSegment(value: 2, label: Text('Off')),
            ],
            selected: {selected},
            onSelectionChanged: (set) {
              final v = set.first;
              state.setNoise(enabled: v != 2, mode: v == 1 ? 1 : 0, level: nc['level'] as int? ?? 8);
            },
          ),
        ],
      ),
    );
  }
}

class EqualizerCard extends StatelessWidget {
  const EqualizerCard({super.key, required this.state, required this.status});
  final SonyState state;
  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final eq = status['eq'] as Map<String, dynamic>?;
    if (eq == null) {
      return const _Card(title: 'Equalizer', child: Text('Not reported yet'));
    }
    final presets = (eq['presets'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final bands = (eq['bands'] as List?)?.cast<int>() ?? const <int>[];
    final current = eq['preset'] as int? ?? 0;
    final peak = bands.isEmpty ? 1 : bands.reduce(math.max).clamp(1, 99);

    return _Card(
      title: 'Equalizer',
      subtitle: 'Applied on the headphones, not in software.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (presets.isNotEmpty)
            DropdownButton<int>(
              value: presets.any((p) => p['id'] == current) ? current : null,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: [
                for (final p in presets)
                  DropdownMenuItem(
                    value: p['id'] as int,
                    child: Text((p['name'] as String?)?.isNotEmpty == true
                        ? p['name'] as String
                        : 'Preset ${p['id']}'),
                  ),
              ],
              onChanged: (v) {
                if (v != null) state.setPreset(v);
              },
            ),
          if (bands.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 56,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final b in bands)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              height: math.max(3, (b / peak) * 40),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2.5),
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Tokens.accent, Color(0x880088FF)],
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text('$b', style: const TextStyle(fontSize: 8)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Device-named settings (sidetone, multipoint, touch panel…).
/// Playback controller state, read-only on this protocol.
class PlaybackCard extends StatelessWidget {
  const PlaybackCard({super.key, required this.state, required this.status});
  final SonyState state;
  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final play = status['playback'] as Map<String, dynamic>?;
    if (play == null) return const SizedBox.shrink();
    final enabled = play['enabled'] == 1;
    final label = (play['state'] as String?) ?? 'Unknown';
    final source = (play['source'] as String?) ?? 'Unknown';
    final playing = play['state'] == 'Playing';
    return _Card(
      title: 'Playback',
      subtitle: enabled ? 'Reported by the headphones.' : 'Playback controller is disabled.',
      child: Row(
        children: [
          IconButton(
            onPressed: enabled ? () => state.setPlaybackControl(0x03) : null,
            icon: const Icon(Icons.skip_previous),
            tooltip: 'Previous',
          ),
          IconButton(
            onPressed: enabled
                ? () => state.setPlaybackControl(playing ? 0x01 : 0x07)
                : null,
            icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
            iconSize: 34,
            tooltip: playing ? 'Pause' : 'Play',
          ),
          IconButton(
            onPressed: enabled ? () => state.setPlaybackControl(0x02) : null,
            icon: const Icon(Icons.skip_next),
            tooltip: 'Next',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              enabled ? '$label · $source' : 'Disabled',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Table-2 read-only settings.
class Table2StatusCard extends StatelessWidget {
  const Table2StatusCard({super.key, required this.state, required this.status});
  final SonyState state;
  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final mho = status['music_hand_over'] as bool?;
    final usb = status['usb_submersion'] as bool?;
    final paired = (status['paired_devices'] as List?)
        ?.whereType<Map<String, dynamic>>()
        .toList();
    final cap = status['pairing_capability'] as Map<String, dynamic>?;
    final event = status['pairing_event'] as Map<String, dynamic>?;
    final pairingMode = status['pairing_mode'] as Map<String, dynamic>?;
    if (mho == null &&
        usb == null &&
        paired == null &&
        cap == null &&
        event == null &&
        pairingMode == null) {
      return const SizedBox.shrink();
    }
    return _Card(
      title: 'Device Link',
      child: Column(
        children: [
          if (mho != null)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Music hand-over'),
              value: mho,
              onChanged: state.setMusicHandOver,
            ),
          if (usb != null) _row('USB submersion', usb ? 'Submerged' : 'Not submerged'),
          if (paired != null && paired.isNotEmpty) ...[
            const Divider(height: 20),
            for (var i = 0; i < paired.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(paired[i]['name'] as String? ?? 'Unknown device'),
                subtitle: Text(paired[i]['address'] as String? ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      paired[i]['connected'] == true ? 'Connected' : 'Paired',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: paired[i]['connected'] == true
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (paired[i]['connected'] == true)
                      TextButton(
                        onPressed: () => _confirmDisconnect(
                          context,
                          state,
                          i,
                          paired[i]['name'] as String? ?? 'device',
                        ),
                        child: const Text('Disconnect'),
                      )
                    else
                      TextButton(
                        onPressed: () => state.connectPairedDevice(i),
                        child: const Text('Connect'),
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                TextButton(
                  onPressed: () => state.setPairingMode(true),
                  child: const Text('Enter pairing mode'),
                ),
                TextButton(
                  onPressed: () => state.setPairingMode(false),
                  child: const Text('Leave'),
                ),
              ],
            ),
          ],
          if (cap != null)
            _row(
              'Connection limit',
              '${cap['max_connected']} connected, ${cap['max_paired']} paired',
            ),
          if (event != null)
            _row(
              'Last pairing action',
              event['result_name'] as String? ?? 'Unknown result',
            ),
          if (pairingMode != null)
            _row(
              'Bluetooth mode',
              pairingMode['name'] as String? ?? 'Unknown',
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text(label),
            const Spacer(),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Future<void> _confirmDisconnect(
    BuildContext context,
    SonyState state,
    int index,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Disconnect $name?'),
        content: const Text(
          "The headset will drop this device's Bluetooth link. It stays paired.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed == true) state.disconnectPairedDevice(index);
  }
}

/// Earpiece fitting detection (earbud models only).
bool isEarbudModel(Map<String, dynamic> status) {
  final model = (status['model'] as String? ?? '').toUpperCase();
  return model.startsWith('WF-') || model.startsWith('WI-') || model.contains('LINKBUDS');
}

/// Earpiece fitting detection (earbud models only). On over-ear headphones the
/// device reports `MODE_OUT` regardless of wear, so the card is hidden.
/// Speak-to-Chat, with detection sensitivity and auto-off time.
class SmartTalkingCard extends StatelessWidget {
  const SmartTalkingCard({super.key, required this.state, required this.status});
  final SonyState state;
  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final st = status['smart_talking'] as Map<String, dynamic>?;
    if (st == null) return const SizedBox.shrink();
    final enabled = st['enabled'] == true;
    final sensitivity = st['sensitivity'] as int? ?? 0;
    final modeOut = st['mode_out'] as int? ?? 1;
    return _Card(
      title: 'Speak-to-Chat',
      subtitle: 'Pauses music when you start talking.',
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enabled'),
            value: enabled,
            onChanged: state.setSmartTalking,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Detection'),
            trailing: DropdownButton<int>(
              value: sensitivity.clamp(0, 2),
              onChanged: enabled
                  ? (v) {
                      if (v != null) state.setSmartTalkingDetail(v, modeOut);
                    }
                  : null,
              items: const [
                DropdownMenuItem(value: 0, child: Text('Auto')),
                DropdownMenuItem(value: 1, child: Text('High')),
                DropdownMenuItem(value: 2, child: Text('Low')),
              ],
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-off'),
            trailing: DropdownButton<int>(
              value: modeOut.clamp(0, 3),
              onChanged: enabled
                  ? (v) {
                      if (v != null) state.setSmartTalkingDetail(sensitivity, v);
                    }
                  : null,
              items: const [
                DropdownMenuItem(value: 0, child: Text('Fast')),
                DropdownMenuItem(value: 1, child: Text('Medium')),
                DropdownMenuItem(value: 2, child: Text('Slow')),
                DropdownMenuItem(value: 3, child: Text('None')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Head gesture on/off.
class HeadGestureCard extends StatelessWidget {
  const HeadGestureCard({super.key, required this.state, required this.status});
  final SonyState state;
  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final enabled = status['head_gesture'] as bool?;
    if (enabled == null) return const SizedBox.shrink();
    return _Card(
      title: 'Head gesture',
      subtitle: 'Nod to answer or end a call.',
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Enabled'),
        value: enabled,
        onChanged: state.setHeadGesture,
      ),
    );
  }
}

/// Music volume, shown only when the controller advertised a range.
class VolumeCard extends StatelessWidget {
  const VolumeCard({super.key, required this.state, required this.status});
  final SonyState state;
  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final music = status['volume'] as Map<String, dynamic>?;
    final call = status['call_volume'] as Map<String, dynamic>?;
    final safeVolume = status['safe_volume'] as Map<String, dynamic>?;
    final adaptiveStarted = status['adaptive_control_started'] as bool?;
    final quickAccess = (status['quick_access'] as List?)
        ?.cast<Map<String, dynamic>>();
    final controlByWearing = status['control_by_wearing'] as bool?;
    final micOnOff = status['mic_on_off'] as bool?;
    final sonyVoiceAssistant = status['sony_voice_assistant'] as bool?;
    final voiceGuidance = status['voice_guidance'] as bool?;
    final voiceGuidanceVolume = status['voice_guidance_volume'] as int?;
    final autoVolume = status['auto_volume'] as bool?;
    final autoStandby = status['auto_standby'] as bool?;
    final autoStandbyEnabled = status['auto_standby_enabled'] as bool?;
    final musicMax = music?['max'] as int? ?? 0;
    final callMax = call?['max'] as int? ?? 0;
    if (musicMax <= 0 &&
        callMax <= 0 &&
        autoVolume == null &&
        autoStandbyEnabled == null) {
      return const SizedBox.shrink();
    }
    return _Card(
      title: 'Volume',
      child: Column(
        children: [
          if (music != null && musicMax > 0)
            _slider(
              'Music',
              music['value'] as int? ?? 0,
              musicMax,
              state.setMusicVolume,
            ),
          if (call != null && callMax > 0)
            _slider('Call', call['value'] as int? ?? 0, callMax, state.setCallVolume),
          if (controlByWearing != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pause when removed'),
              value: controlByWearing,
              onChanged: (v) => state.setControlByWearing(v),
            ),
          if (micOnOff != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mic by headphone'),
              value: micOnOff,
              onChanged: (v) => state.setMicOnOff(v),
            ),
          if (sonyVoiceAssistant != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sony Voice Assistant'),
              value: sonyVoiceAssistant,
              onChanged: (v) => state.setSonyVoiceAssistant(v),
            ),
          if (adaptiveStarted != null)
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              title: const Text('Adaptive control'),
              value: adaptiveStarted,
              onChanged: (v) => state.setAdaptiveControl(v),
            ),
          if (quickAccess != null && quickAccess.length == 2)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Quick Access',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (var i = 0; i < 2; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButton<int>(
                              isExpanded: true,
                              value: quickAccess[i]['value'] as int?,
                              items: quickAccessOptions
                                  .map((o) => DropdownMenuItem<int>(
                                        value: o.$1,
                                        child: Text(o.$2, overflow: TextOverflow.ellipsis),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                final updated = [
                                  quickAccess[0]['value'] as int,
                                  quickAccess[1]['value'] as int,
                                ];
                                updated[i] = v;
                                state.setQuickAccessFunctions(updated);
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (voiceGuidance != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Voice guidance'),
              value: voiceGuidance,
              onChanged: (v) => state.setVoiceGuidance(v),
            ),
          if (voiceGuidanceVolume != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Guidance volume'),
              trailing: SizedBox(
                width: 140,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: () => state.setVoiceGuidanceVolume(
                          (voiceGuidanceVolume - 1).clamp(-128, 127)),
                    ),
                    Text('$voiceGuidanceVolume'),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () => state.setVoiceGuidanceVolume(
                          (voiceGuidanceVolume + 1).clamp(-128, 127)),
                    ),
                  ],
                ),
              ),
            ),
          if (safeVolume != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Safe volume'),
              trailing: DropdownButton<int>(
                value: (safeVolume['level'] as int? ?? 0).clamp(0, 1),
                onChanged: (v) {
                  if (v != null) state.setSafeVolume(v);
                },
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Normal')),
                  DropdownMenuItem(value: 1, child: Text('Sensitive')),
                ],
              ),
            ),
          if (autoVolume != null)
            _readOnlyRow(
              'Auto volume',
              autoVolume ? 'On (read-only)' : 'Off (read-only)',
            ),
          if (autoStandbyEnabled != null)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                autoStandby == false
                    ? 'Auto standby (unavailable)'
                    : 'Auto standby (15 min)',
              ),
              value: autoStandbyEnabled,
              onChanged: state.setAutoStandby,
            ),
        ],
      ),
    );
  }

  Widget _readOnlyRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text(label),
            const Spacer(),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _slider(String label, int raw, int max, void Function(int) onSet) {
    final value = raw.clamp(0, max);
    return Row(
      children: [
        SizedBox(width: 52, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            max: max.toDouble(),
            divisions: max,
            label: '$value',
            onChanged: (v) => onSet(v.round()),
          ),
        ),
        SizedBox(
          width: 28,
          child: Text('$value', textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

/// Listening mode: the device's BGM and Cinema settings combined.
class ListeningModeCard extends StatelessWidget {
  const ListeningModeCard({super.key, required this.state, required this.status});
  final SonyState state;
  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final listen = status['listening'] as Map<String, dynamic>?;
    if (listen == null) return const SizedBox.shrink();
    final mode = listen['mode_code'] as int? ?? 0;
    return _Card(
      title: 'Listening mode',
      subtitle: 'Reported from the BGM and Cinema settings.',
      child: SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('Standard')),
          ButtonSegment(value: 1, label: Text('BGM')),
          ButtonSegment(value: 2, label: Text('Cinema')),
        ],
        selected: {mode},
        onSelectionChanged: (selection) => state.setListeningMode(selection.first),
      ),
    );
  }
}

class EarpieceFittingCard extends StatelessWidget {
  const EarpieceFittingCard({super.key, required this.status});
  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final fit = status['earpiece_fitting'] as Map<String, dynamic>?;
    if (fit == null) return const SizedBox.shrink();
    final inEar = fit['in_ear'] == true;
    final enabled = fit['detection_enabled'] == true;
    return _Card(
      title: 'Earpiece fitting',
      subtitle: enabled ? 'Reported by the earbuds.' : 'Detection is turned off.',
      child: Text(
        inEar ? 'In ear' : 'Out of ear',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class DeviceSettingsCard extends StatelessWidget {
  const DeviceSettingsCard({super.key, required this.state, required this.status});
  final SonyState state;
  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final gs = (status['gs'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    if (gs.isEmpty) return const SizedBox.shrink();
    return _Card(
      title: 'Device Settings',
      subtitle: 'Named by the headphones themselves.',
      child: Column(
        children: [
          for (final item in gs)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text((item['title'] as String?) ?? ''),
              subtitle: (item['detail'] as String?)?.isNotEmpty == true
                  ? Text(item['detail'] as String)
                  : null,
              value: item['value'] == 1,
              onChanged: item['value'] == null
                  ? null
                  : (on) => state.setGeneralSetting(item['type'] as int, on),
            ),
          TextButton(
            onPressed: () => _confirmPowerOff(context),
            child: const Text(
              'Power off headphones',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPowerOff(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Power off headphones?'),
        content: const Text(
          'The control link will drop. Turn the headphones back on to reconnect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Power Off'),
          ),
        ],
      ),
    );
    if (ok == true) state.powerOff();
  }
}

/// Voice assistant, whose options come from the device.
class VoiceAssistantCard extends StatelessWidget {
  const VoiceAssistantCard({super.key, required this.state, required this.status});
  final SonyState state;
  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final va = status['voice_assistant'] as Map<String, dynamic>?;
    if (va == null) return const SizedBox.shrink();
    final options = (va['supported'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final current = va['current'] as int? ?? 0xFF;
    return _Card(
      title: 'Voice Assistant',
      subtitle: 'Assigned on the headphones.',
      child: DropdownButton<int>(
        value: current,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        items: [
          for (final o in options)
            DropdownMenuItem(value: o['value'] as int, child: Text((o['name'] as String?) ?? '')),
          const DropdownMenuItem(value: 0xFF, child: Text('Not set')),
        ],
        onChanged: (v) {
          if (v != null) state.setVoiceAssistant(v);
        },
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9F0A).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF9F0A), size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
