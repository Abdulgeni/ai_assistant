import 'dart:async';

import 'package:ai_assistant/data/voice/voice_ports.dart';
import 'package:ai_assistant/domain/entities/voice_state.dart';

class FakeClock {
  DateTime now = DateTime(2026, 1, 1, 12);

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

class FakeRecognizer implements SpeechRecognizerPort {
  bool listening = false;
  bool initOk = true;
  String? resolved = 'ar_SA';
  Object? listenError;
  int listenCalls = 0;
  int cancelCalls = 0;
  int resolveCalls = 0;

  void Function(String status)? statusCallback;
  void Function(RecognizerError error)? errorCallback;
  final List<void Function(RecognizerResult result)> resultCallbacks =
      <void Function(RecognizerResult result)>[];
  void Function(double level)? levelCallback;

  @override
  bool get isListening => listening;

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(RecognizerError error) onError,
  }) async {
    statusCallback = onStatus;
    errorCallback = onError;
    return initOk;
  }

  @override
  Future<String?> resolveLocale(String requested) async {
    resolveCalls++;
    return resolved;
  }

  @override
  Future<void> listen({
    required String localeId,
    required Duration listenFor,
    required Duration pauseFor,
    required void Function(RecognizerResult result) onResult,
    required void Function(double level) onSoundLevel,
  }) async {
    if (listenError != null) throw listenError!;
    listening = true;
    listenCalls++;
    resultCallbacks.add(onResult);
    levelCallback = onSoundLevel;
  }

  @override
  Future<void> stop() async {
    listening = false;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    listening = false;
  }

  void partial(String text, {int callback = -1}) => _result(
        RecognizerResult(text, isFinal: false),
        callback,
      );

  void finalResult(String text, {int callback = -1}) => _result(
        RecognizerResult(text, isFinal: true),
        callback,
      );

  void _result(RecognizerResult result, int callback) {
    final int index = callback < 0 ? resultCallbacks.length - 1 : callback;
    resultCallbacks[index](result);
  }

  void status(String value) => statusCallback?.call(value);

  void error(String message, {bool permanent = false}) =>
      errorCallback?.call(RecognizerError(message, permanent: permanent));

  void level(double value) => levelCallback?.call(value);
}

class FakeSynthesizer implements SpeechSynthesizerPort {
  bool active = false;
  bool languageAvailable = true;
  Object? speakError;
  final List<String> spoken = <String>[];
  final List<String> languagesSet = <String>[];
  int stopCalls = 0;

  void Function()? _onStart;
  void Function()? _onComplete;
  void Function()? _onCancel;
  void Function(String message)? _onError;

  @override
  Future<bool> isLanguageAvailable(String languageTag) async => languageAvailable;

  @override
  Future<void> setLanguage(String languageTag) async {
    languagesSet.add(languageTag);
  }

  @override
  void bind({
    required void Function() onStart,
    required void Function() onComplete,
    required void Function() onCancel,
    required void Function(String message) onError,
  }) {
    _onStart = onStart;
    _onComplete = onComplete;
    _onCancel = onCancel;
    _onError = onError;
  }

  @override
  Future<void> speak(String text) async {
    if (speakError != null) throw speakError!;
    active = true;
    spoken.add(text);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    active = false;
  }

  void start() => _onStart?.call();

  void complete() {
    active = false;
    _onComplete?.call();
  }

  void spuriousComplete() => _onComplete?.call();

  void spuriousCancel() => _onCancel?.call();

  void osCancel() {
    active = false;
    _onCancel?.call();
  }

  void error(String message) => _onError?.call(message);
}

class FakeAudioSession implements AudioSessionPort {
  bool active = false;
  bool activateOk = true;
  int configureCalls = 0;
  int setActiveTrueCalls = 0;

  final StreamController<bool> _interruptions = StreamController<bool>.broadcast();
  final StreamController<void> _noisy = StreamController<void>.broadcast();

  @override
  Future<void> configureForVoice() async {
    configureCalls++;
  }

  @override
  Future<bool> setActive({required bool active}) async {
    if (active) setActiveTrueCalls++;
    if (active && !activateOk) return false;
    this.active = active;
    return true;
  }

  @override
  Stream<bool> get interruptions => _interruptions.stream;

  @override
  Stream<void> get becomingNoisy => _noisy.stream;

  bool get hasListeners => _interruptions.hasListener || _noisy.hasListener;

  void interruption({required bool began}) => _interruptions.add(began);

  void noisy() => _noisy.add(null);
}

class FakePermissions implements VoicePermissionPort {
  VoicePermissionStatus status = VoicePermissionStatus.granted;
  VoicePermissionStatus requestResult = VoicePermissionStatus.granted;

  @override
  Future<VoicePermissionStatus> check() async => status;

  @override
  Future<VoicePermissionStatus> request() async {
    status = requestResult;
    return requestResult;
  }
}
