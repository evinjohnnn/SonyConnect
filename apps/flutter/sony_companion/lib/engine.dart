// Dart bindings for the Rust control engine.
//
// State crosses the boundary as one JSON document (`mdr_state_json`) rather
// than a mirrored C struct, so this file cannot silently disagree with the
// engine about struct layout — the failure mode that makes hand-written FFI
// bindings dangerous.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final class MdrBuffer extends Struct {
  external Pointer<Uint8> data;
  @Size()
  external int len;
  @Size()
  external int cap;
}

typedef _NewNative = Pointer<Void> Function();
typedef _NewDart = Pointer<Void> Function();

typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);

typedef _ConnectNative = Int32 Function(Pointer<Void>, Uint64, Pointer<MdrBuffer>);
typedef _ConnectDart = int Function(Pointer<Void>, int, Pointer<MdrBuffer>);

typedef _ReceiveNative = Int32 Function(
    Pointer<Void>, Pointer<Uint8>, Size, Uint64, Pointer<MdrBuffer>);
typedef _ReceiveDart = int Function(
    Pointer<Void>, Pointer<Uint8>, int, int, Pointer<MdrBuffer>);

typedef _PollNative = Int32 Function(Pointer<Void>, Uint64, Pointer<MdrBuffer>);
typedef _PollDart = int Function(Pointer<Void>, int, Pointer<MdrBuffer>);

typedef _SetNoiseNative = Int32 Function(
    Pointer<Void>, Bool, Uint8, Uint8, Uint8, Uint64, Pointer<MdrBuffer>);
typedef _SetNoiseDart = int Function(
    Pointer<Void>, bool, int, int, int, int, Pointer<MdrBuffer>);

typedef _SetEqNative = Int32 Function(
    Pointer<Void>, Uint8, Pointer<Uint8>, Size, Uint64, Pointer<MdrBuffer>);
typedef _SetEqDart = int Function(
    Pointer<Void>, int, Pointer<Uint8>, int, int, Pointer<MdrBuffer>);

typedef _SetBassNative = Int32 Function(
    Pointer<Void>, Int8, Uint64, Pointer<MdrBuffer>);
typedef _SetBassDart = int Function(Pointer<Void>, int, int, Pointer<MdrBuffer>);

typedef _SetAdaptiveNative = Int32 Function(
    Pointer<Void>, Bool, Uint64, Pointer<MdrBuffer>);
typedef _SetAdaptiveDart = int Function(
    Pointer<Void>, bool, int, Pointer<MdrBuffer>);

typedef _PairingDeviceActionNative = Int32 Function(
    Pointer<Void>, Size, Uint64, Pointer<MdrBuffer>);
typedef _PairingDeviceActionDart = int Function(
    Pointer<Void>, int, int, Pointer<MdrBuffer>);

typedef _PairingModeNative = Int32 Function(
    Pointer<Void>, Bool, Uint64, Pointer<MdrBuffer>);
typedef _PairingModeDart = int Function(
    Pointer<Void>, bool, int, Pointer<MdrBuffer>);

typedef _SetQuickAccessNative = Int32 Function(
    Pointer<Void>, Pointer<Uint8>, Size, Uint64, Pointer<MdrBuffer>);
typedef _SetQuickAccessDart = int Function(
    Pointer<Void>, Pointer<Uint8>, int, int, Pointer<MdrBuffer>);

typedef _SetGsNative = Int32 Function(
    Pointer<Void>, Uint8, Bool, Uint64, Pointer<MdrBuffer>);
typedef _SetGsDart = int Function(Pointer<Void>, int, bool, int, Pointer<MdrBuffer>);

typedef _SetVaNative = Int32 Function(Pointer<Void>, Uint8, Uint64, Pointer<MdrBuffer>);
typedef _SetVaDart = int Function(Pointer<Void>, int, int, Pointer<MdrBuffer>);

typedef _PlaybackControlNative = Int32 Function(
    Pointer<Void>, Uint8, Uint64, Pointer<MdrBuffer>);
typedef _PlaybackControlDart = int Function(Pointer<Void>, int, int, Pointer<MdrBuffer>);

typedef _ListeningNative = Int32 Function(
    Pointer<Void>, Uint8, Uint64, Pointer<MdrBuffer>);
typedef _ListeningDart = int Function(Pointer<Void>, int, int, Pointer<MdrBuffer>);

typedef _MusicHandOverNative = Int32 Function(
    Pointer<Void>, Bool, Uint64, Pointer<MdrBuffer>);
typedef _MusicHandOverDart = int Function(Pointer<Void>, bool, int, Pointer<MdrBuffer>);

typedef _VolumeNative = Int32 Function(
    Pointer<Void>, Uint8, Uint64, Pointer<MdrBuffer>);
typedef _VolumeDart = int Function(Pointer<Void>, int, int, Pointer<MdrBuffer>);

typedef _CallVolumeNative = Int32 Function(
    Pointer<Void>, Uint8, Uint64, Pointer<MdrBuffer>);
typedef _CallVolumeDart = int Function(Pointer<Void>, int, int, Pointer<MdrBuffer>);

typedef _AutoStandbyNative = Int32 Function(
    Pointer<Void>, Bool, Uint64, Pointer<MdrBuffer>);
typedef _AutoStandbyDart = int Function(Pointer<Void>, bool, int, Pointer<MdrBuffer>);

typedef _ControlByWearingNative = Int32 Function(
    Pointer<Void>, Bool, Uint64, Pointer<MdrBuffer>);
typedef _ControlByWearingDart = int Function(
    Pointer<Void>, bool, int, Pointer<MdrBuffer>);

typedef _MicOnOffNative = Int32 Function(
    Pointer<Void>, Bool, Uint64, Pointer<MdrBuffer>);
typedef _MicOnOffDart = int Function(Pointer<Void>, bool, int, Pointer<MdrBuffer>);

typedef _SonyVoiceAssistantNative = Int32 Function(
    Pointer<Void>, Bool, Uint64, Pointer<MdrBuffer>);
typedef _SonyVoiceAssistantDart = int Function(
    Pointer<Void>, bool, int, Pointer<MdrBuffer>);

typedef _VoiceGuidanceNative = Int32 Function(
    Pointer<Void>, Bool, Uint64, Pointer<MdrBuffer>);
typedef _VoiceGuidanceDart = int Function(Pointer<Void>, bool, int, Pointer<MdrBuffer>);

typedef _VoiceGuidanceVolumeNative = Int32 Function(
    Pointer<Void>, Int8, Uint64, Pointer<MdrBuffer>);
typedef _VoiceGuidanceVolumeDart = int Function(
    Pointer<Void>, int, int, Pointer<MdrBuffer>);

typedef _SafeVolumeNative = Int32 Function(
    Pointer<Void>, Uint8, Uint64, Pointer<MdrBuffer>);
typedef _SafeVolumeDart = int Function(Pointer<Void>, int, int, Pointer<MdrBuffer>);

typedef _HeadGestureNative = Int32 Function(
    Pointer<Void>, Bool, Uint64, Pointer<MdrBuffer>);
typedef _HeadGestureDart = int Function(Pointer<Void>, bool, int, Pointer<MdrBuffer>);

typedef _PowerOffNative = Int32 Function(Pointer<Void>, Uint64, Pointer<MdrBuffer>);
typedef _PowerOffDart = int Function(Pointer<Void>, int, Pointer<MdrBuffer>);

typedef _SmartTalkingNative = Int32 Function(
    Pointer<Void>, Bool, Uint64, Pointer<MdrBuffer>);
typedef _SmartTalkingDart = int Function(Pointer<Void>, bool, int, Pointer<MdrBuffer>);

typedef _SmartTalkingDetailNative = Int32 Function(
    Pointer<Void>, Uint8, Uint8, Uint64, Pointer<MdrBuffer>);
typedef _SmartTalkingDetailDart = int Function(
    Pointer<Void>, int, int, int, Pointer<MdrBuffer>);

typedef _JsonNative = IntPtr Function(Pointer<Void>, Pointer<Char>, Size);
typedef _JsonDart = int Function(Pointer<Void>, Pointer<Char>, int);

typedef _BytesFreeNative = Void Function(Pointer<MdrBuffer>);
typedef _BytesFreeDart = void Function(Pointer<MdrBuffer>);

typedef _VersionNative = Pointer<Char> Function();
typedef _VersionDart = Pointer<Char> Function();

const int mdrOk = 0;
const int mdrNoData = 3;

/// A session with one headphone.
class MdrEngine {
  MdrEngine._(this._lib, this._handle);

  final DynamicLibrary _lib;
  Pointer<Void> _handle;

  late final _FreeDart _free =
      _lib.lookupFunction<_FreeNative, _FreeDart>('mdr_session_free');
  late final _ConnectDart _connect =
      _lib.lookupFunction<_ConnectNative, _ConnectDart>('mdr_connect');
  late final _ReceiveDart _receive =
      _lib.lookupFunction<_ReceiveNative, _ReceiveDart>('mdr_receive');
  late final _PollDart _poll =
      _lib.lookupFunction<_PollNative, _PollDart>('mdr_poll');
  late final _SetNoiseDart _setNoise = _lib
      .lookupFunction<_SetNoiseNative, _SetNoiseDart>('mdr_set_noise_control');
  late final _SetEqDart _setEq =
      _lib.lookupFunction<_SetEqNative, _SetEqDart>('mdr_eq_set_preset');
  late final _SetBassDart _setBass = _lib
      .lookupFunction<_SetBassNative, _SetBassDart>('mdr_eq_set_clear_bass');
  late final _SetGsDart _setGs =
      _lib.lookupFunction<_SetGsNative, _SetGsDart>('mdr_set_gs_setting');
  late final _PlaybackControlDart _playback =
      _lib.lookupFunction<_PlaybackControlNative, _PlaybackControlDart>(
          'mdr_playback_control');
  late final _ListeningDart _listening =
      _lib.lookupFunction<_ListeningNative, _ListeningDart>(
          'mdr_set_listening_mode');
  late final _MusicHandOverDart _musicHandOver =
      _lib.lookupFunction<_MusicHandOverNative, _MusicHandOverDart>(
          'mdr_set_music_hand_over');
  late final _PairingDeviceActionDart _pairingConnect =
      _lib.lookupFunction<_PairingDeviceActionNative, _PairingDeviceActionDart>(
          'mdr_pairing_connect');
  late final _PairingDeviceActionDart _pairingDisconnect =
      _lib.lookupFunction<_PairingDeviceActionNative, _PairingDeviceActionDart>(
          'mdr_pairing_disconnect');
  late final _PairingModeDart _pairingMode =
      _lib.lookupFunction<_PairingModeNative, _PairingModeDart>(
          'mdr_pairing_set_mode');
  late final _VolumeDart _volume =
      _lib.lookupFunction<_VolumeNative, _VolumeDart>('mdr_set_music_volume');
  late final _CallVolumeDart _callVolume =
      _lib.lookupFunction<_CallVolumeNative, _CallVolumeDart>('mdr_set_call_volume');
  late final _AutoStandbyDart _autoStandby =
      _lib.lookupFunction<_AutoStandbyNative, _AutoStandbyDart>(
          'mdr_set_auto_standby');
  late final _PowerOffDart _powerOff =
      _lib.lookupFunction<_PowerOffNative, _PowerOffDart>('mdr_power_off');
  late final _ControlByWearingDart _controlByWearing =
      _lib.lookupFunction<_ControlByWearingNative, _ControlByWearingDart>(
          'mdr_set_control_by_wearing');
  late final _SetAdaptiveDart _setAdaptive =
      _lib.lookupFunction<_SetAdaptiveNative, _SetAdaptiveDart>(
          'mdr_set_adaptive_control');
  late final _SetQuickAccessDart _setQuickAccess =
      _lib.lookupFunction<_SetQuickAccessNative, _SetQuickAccessDart>(
          'mdr_set_quick_access_functions');
  late final _MicOnOffDart _micOnOff =
      _lib.lookupFunction<_MicOnOffNative, _MicOnOffDart>('mdr_set_mic_on_off');
  late final _SonyVoiceAssistantDart _sonyVoiceAssistant =
      _lib.lookupFunction<_SonyVoiceAssistantNative, _SonyVoiceAssistantDart>(
          'mdr_set_sony_voice_assistant');
  late final _VoiceGuidanceDart _voiceGuidance =
      _lib.lookupFunction<_VoiceGuidanceNative, _VoiceGuidanceDart>(
          'mdr_set_voice_guidance');
  late final _VoiceGuidanceVolumeDart _voiceGuidanceVolume =
      _lib.lookupFunction<_VoiceGuidanceVolumeNative, _VoiceGuidanceVolumeDart>(
          'mdr_set_voice_guidance_volume');
  late final _SafeVolumeDart _safeVolume =
      _lib.lookupFunction<_SafeVolumeNative, _SafeVolumeDart>(
          'mdr_set_safe_volume');
  late final _HeadGestureDart _headGesture =
      _lib.lookupFunction<_HeadGestureNative, _HeadGestureDart>(
          'mdr_set_head_gesture');
  late final _SmartTalkingDart _smartTalking =
      _lib.lookupFunction<_SmartTalkingNative, _SmartTalkingDart>(
          'mdr_set_smart_talking');
  late final _SmartTalkingDetailDart _smartTalkingDetail =
      _lib.lookupFunction<_SmartTalkingDetailNative, _SmartTalkingDetailDart>(
          'mdr_set_smart_talking_detail');
  late final _JsonDart _json =
      _lib.lookupFunction<_JsonNative, _JsonDart>('mdr_state_json');
  late final _SetVaDart _setVa =
      _lib.lookupFunction<_SetVaNative, _SetVaDart>('mdr_set_voice_assistant');
  late final _BytesFreeDart _bytesFree =
      _lib.lookupFunction<_BytesFreeNative, _BytesFreeDart>('mdr_bytes_free');
  late final _VersionDart _version =
      _lib.lookupFunction<_VersionNative, _VersionDart>('mdr_version');

  /// Open the shared library and create a session.
  static MdrEngine create() {
    final lib = _openLibrary();
    final newFn = lib.lookupFunction<_NewNative, _NewDart>('mdr_session_new');
    final handle = newFn();
    if (handle == nullptr) {
      throw StateError('could not allocate the protocol engine');
    }
    return MdrEngine._(lib, handle);
  }

  static DynamicLibrary _openLibrary() {
    final override = Platform.environment['MDR_FFI_PATH'];
    if (override != null && override.isNotEmpty) {
      return DynamicLibrary.open(override);
    }
    final name = Platform.isWindows
        ? 'mdr_ffi.dll'
        : Platform.isMacOS
            ? 'libmdr_ffi.dylib'
            : 'libmdr_ffi.so';
    // Prefer a copy shipped beside the executable, then the plain name.
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final beside = File('$exeDir/$name');
    if (beside.existsSync()) return DynamicLibrary.open(beside.path);
    return DynamicLibrary.open(name);
  }

  String get version => _version().cast<Utf8>().toDartString();

  /// Reads the whole state as a JSON map.
  Map<String, dynamic> snapshot() {
    const cap = 4096;
    final buf = calloc<Char>(cap);
    try {
      final n = _json(_handle, buf, cap);
      if (n <= 0) return const {};
      return jsonDecode(buf.cast<Utf8>().toDartString(length: n)) as Map<String, dynamic>;
    } finally {
      calloc.free(buf);
    }
  }

  /// Begin the handshake. Returns bytes to write, or null.
  Uint8List? connect(int nowMs) => _collect((out) => _connect(_handle, nowMs, out));

  /// Feed received bytes; returns follow-up bytes to write, or null.
  Uint8List? receive(Uint8List data, int nowMs) {
    final ptr = calloc<Uint8>(data.length);
    try {
      ptr.asTypedList(data.length).setAll(0, data);
      return _collect((out) => _receive(_handle, ptr, data.length, nowMs, out));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Retry / queued-write pump. Returns bytes to write, or null.
  Uint8List? poll(int nowMs) => _collect((out) => _poll(_handle, nowMs, out));

  Uint8List? setNoiseControl({
    required bool enabled,
    required int mode,
    required int ambientMode,
    required int level,
    required int nowMs,
  }) =>
      _collect((out) => _setNoise(_handle, enabled, mode, ambientMode, level, nowMs, out));

  Uint8List? setEqualizerPreset({
    required int preset,
    required List<int> bands,
    required int nowMs,
  }) {
    final ptr = calloc<Uint8>(bands.isEmpty ? 1 : bands.length);
    try {
      for (var i = 0; i < bands.length; i++) {
        ptr[i] = bands[i] & 0xFF;
      }
      return _collect((out) => _setEq(_handle, preset, ptr, bands.length, nowMs, out));
    } finally {
      calloc.free(ptr);
    }
  }

  Uint8List? setPlaybackControl(int control, int nowMs) =>
      _collect((out) => _playback(_handle, control, nowMs, out));

  Uint8List? setListeningMode(int mode, int nowMs) =>
      _collect((out) => _listening(_handle, mode, nowMs, out));

  Uint8List? setMusicHandOver(bool enabled, int nowMs) =>
      _collect((out) => _musicHandOver(_handle, enabled, nowMs, out));

  Uint8List? connectPairedDevice(int index, int nowMs) =>
      _collect((out) => _pairingConnect(_handle, index, nowMs, out));

  Uint8List? disconnectPairedDevice(int index, int nowMs) =>
      _collect((out) => _pairingDisconnect(_handle, index, nowMs, out));

  Uint8List? setPairingMode(bool pairing, int nowMs) =>
      _collect((out) => _pairingMode(_handle, pairing, nowMs, out));

  Uint8List? setMusicVolume(int volume, int nowMs) =>
      _collect((out) => _volume(_handle, volume, nowMs, out));

  Uint8List? setCallVolume(int volume, int nowMs) =>
      _collect((out) => _callVolume(_handle, volume, nowMs, out));

  Uint8List? setAutoStandby(bool enabled, int nowMs) =>
      _collect((out) => _autoStandby(_handle, enabled, nowMs, out));

  Uint8List? setControlByWearing(bool enabled, int nowMs) =>
      _collect((out) => _controlByWearing(_handle, enabled, nowMs, out));

  Uint8List? setAdaptiveControl(bool start, int nowMs) =>
      _collect((out) => _setAdaptive(_handle, start, nowMs, out));

  Uint8List? setQuickAccessFunctions(List<int> functions, int nowMs) {
    final ptr = calloc<Uint8>(functions.isEmpty ? 1 : functions.length);
    try {
      for (var i = 0; i < functions.length; i++) {
        ptr[i] = functions[i] & 0xFF;
      }
      return _collect(
          (out) => _setQuickAccess(_handle, ptr, functions.length, nowMs, out));
    } finally {
      calloc.free(ptr);
    }
  }

  Uint8List? setMicOnOff(bool enabled, int nowMs) =>
      _collect((out) => _micOnOff(_handle, enabled, nowMs, out));

  Uint8List? setSonyVoiceAssistant(bool enabled, int nowMs) =>
      _collect((out) => _sonyVoiceAssistant(_handle, enabled, nowMs, out));

  Uint8List? setVoiceGuidance(bool enabled, int nowMs) =>
      _collect((out) => _voiceGuidance(_handle, enabled, nowMs, out));

  Uint8List? setVoiceGuidanceVolume(int volume, int nowMs) =>
      _collect((out) => _voiceGuidanceVolume(_handle, volume, nowMs, out));

  Uint8List? setSafeVolume(int level, int nowMs) =>
      _collect((out) => _safeVolume(_handle, level, nowMs, out));

  Uint8List? setHeadGesture(bool enabled, int nowMs) =>
      _collect((out) => _headGesture(_handle, enabled, nowMs, out));

  Uint8List? powerOff(int nowMs) =>
      _collect((out) => _powerOff(_handle, nowMs, out));

  Uint8List? setSmartTalking(bool enabled, int nowMs) =>
      _collect((out) => _smartTalking(_handle, enabled, nowMs, out));

  Uint8List? setSmartTalkingDetail(int sensitivity, int modeOut, int nowMs) =>
      _collect((out) => _smartTalkingDetail(
          _handle, sensitivity, modeOut, nowMs, out));

  Uint8List? setGeneralSetting(int gsType, bool enabled, int nowMs) =>
      _collect((out) => _setGs(_handle, gsType, enabled, nowMs, out));

  Uint8List? setVoiceAssistant(int value, int nowMs) =>
      _collect((out) => _setVa(_handle, value, nowMs, out));

  Uint8List? setClearBass(int level, int nowMs) =>
      _collect((out) => _setBass(_handle, level, nowMs, out));

  Uint8List? _collect(int Function(Pointer<MdrBuffer>) call) {
    final out = calloc<MdrBuffer>();
    try {
      final status = call(out);
      if (status != mdrOk || out.ref.data == nullptr || out.ref.len == 0) {
        return null;
      }
      return Uint8List.fromList(out.ref.data.asTypedList(out.ref.len));
    } finally {
      _bytesFree(out);
      calloc.free(out);
    }
  }

  void dispose() {
    if (_handle != nullptr) {
      _free(_handle);
      _handle = nullptr;
    }
  }
}
