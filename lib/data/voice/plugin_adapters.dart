import 'package:ai_assistant/data/voice/voice_ports.dart';
import 'package:ai_assistant/data/voice/voice_text_utils.dart';
import 'package:ai_assistant/domain/entities/voice_state.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

// Thin wrappers over the plugins. They hold no logic worth testing off-device;
// everything interesting lives in PlatformVoiceEngine.

/// `speech_to_text`. The plugin's `initialize` takes its status/error callbacks
/// once, so they are forwarded through fields and the plugin is initialized at
/// most once successfully.
final class SpeechToTextRecognizer implements SpeechRecognizerPort {
  SpeechToTextRecognizer({SpeechToText? speech})
      : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  void Function(String status)? _onStatus;
  void Function(RecognizerError error)? _onError;
  Future<bool>? _initializing;

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(RecognizerError error) onError,
  }) {
    _onStatus = onStatus;
    _onError = onError;
    return _ensureInitialized();
  }

  Future<bool> _ensureInitialized() => _initializing ??= _speech
          .initialize(
        onStatus: (String status) => _onStatus?.call(status),
        onError: (SpeechRecognitionError error) => _onError?.call(
          RecognizerError(error.errorMsg, permanent: error.permanent),
        ),
        // Avoids the extra Bluetooth-connect permission on Android 12+.
        options: <SpeechConfigOption>[SpeechToText.androidNoBluetooth],
      )
          .then((bool ok) {
        if (!ok) _initializing = null; // allow a retry after the user grants
        return ok;
      });

  @override
  Future<String?> resolveLocale(String requested) async {
    if (!await _ensureInitialized()) return null;
    final List<LocaleName> locales = await _speech.locales();
    return matchLocaleId(
      requested,
      locales.map((LocaleName l) => l.localeId).toList(),
    );
  }

  @override
  Future<void> listen({
    required String localeId,
    required Duration listenFor,
    required Duration pauseFor,
    required void Function(RecognizerResult result) onResult,
    required void Function(double level) onSoundLevel,
  }) async {
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) =>
          onResult(RecognizerResult(r.recognizedWords, isFinal: r.finalResult)),
      onSoundLevelChange: onSoundLevel,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        listenFor: listenFor,
        pauseFor: pauseFor,
        localeId: localeId,
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}

/// `flutter_tts`. Only start/complete/cancel/error handlers exist (there is no
/// `isPlaying`), which is why the engine tracks playback state itself. The iOS
/// audio category is deliberately NOT set here: `audio_session` owns it.
final class FlutterTtsSynthesizer implements SpeechSynthesizerPort {
  FlutterTtsSynthesizer({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  @override
  Future<bool> isLanguageAvailable(String languageTag) async {
    // Platforms report true/false or 1/0.
    final dynamic result = await _tts.isLanguageAvailable(languageTag);
    return result == true || result == 1;
  }

  @override
  Future<void> setLanguage(String languageTag) async {
    await _tts.setLanguage(languageTag);
  }

  @override
  void bind({
    required void Function() onStart,
    required void Function() onComplete,
    required void Function() onCancel,
    required void Function(String message) onError,
  }) {
    _tts.setStartHandler(onStart);
    _tts.setCompletionHandler(onComplete);
    _tts.setCancelHandler(onCancel);
    _tts.setErrorHandler((dynamic message) => onError('$message'));
  }

  @override
  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}

/// `audio_session`. Apply this AFTER the other audio plugins are initialized;
/// they overwrite each other's audio-session settings otherwise.
final class AudioSessionAdapter implements AudioSessionPort {
  @override
  Future<void> configureForVoice() async {
    final AudioSession session = await AudioSession.instance;
    await session.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker |
                AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ),
    );
  }

  @override
  Future<bool> setActive({required bool active}) async {
    final AudioSession session = await AudioSession.instance;
    return session.setActive(active);
  }

  @override
  Stream<bool> get interruptions async* {
    final AudioSession session = await AudioSession.instance;
    yield* session.interruptionEventStream
        .where((AudioInterruptionEvent e) => e.type != AudioInterruptionType.duck)
        .map((AudioInterruptionEvent e) => e.begin);
  }

  @override
  Stream<void> get becomingNoisy async* {
    final AudioSession session = await AudioSession.instance;
    yield* session.becomingNoisyEventStream;
  }
}

/// `permission_handler`. Android needs the microphone; iOS needs the
/// microphone AND speech recognition.
final class PermissionHandlerAdapter implements VoicePermissionPort {
  const PermissionHandlerAdapter();

  List<Permission> get _needed => defaultTargetPlatform == TargetPlatform.iOS
      ? <Permission>[Permission.microphone, Permission.speech]
      : <Permission>[Permission.microphone];

  @override
  Future<VoicePermissionStatus> check() async {
    final List<VoicePermissionStatus> statuses = <VoicePermissionStatus>[
      for (final Permission permission in _needed) _map(await permission.status),
    ];
    return combinePermissionStatuses(statuses);
  }

  @override
  Future<VoicePermissionStatus> request() async {
    final Map<Permission, PermissionStatus> result = await _needed.request();
    return combinePermissionStatuses(
      result.values.map(_map).toList(growable: false),
    );
  }

  VoicePermissionStatus _map(PermissionStatus status) {
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return VoicePermissionStatus.granted;
    }
    if (status.isPermanentlyDenied) return VoicePermissionStatus.permanentlyDenied;
    if (status.isRestricted) return VoicePermissionStatus.restricted;
    return VoicePermissionStatus.denied;
  }
}
