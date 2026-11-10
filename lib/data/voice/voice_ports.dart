import 'package:ai_assistant/domain/entities/voice_state.dart';

/// A recognition result from the platform recognizer.
final class RecognizerResult {
  const RecognizerResult(this.text, {required this.isFinal});

  final String text;
  final bool isFinal;
}

final class RecognizerError {
  const RecognizerError(this.message, {required this.permanent});

  /// Platform error code string (e.g. `error_no_match`).
  final String message;
  final bool permanent;
}

/// Speech-to-text, as the engine needs it. The adapter wraps `speech_to_text`.
abstract interface class SpeechRecognizerPort {
  /// What the platform recognizer is doing right now (not what the engine
  /// believes). The engine consults this so a recognizer that is still live
  /// after a final result is never overlapped with audio output.
  bool get isListening;

  /// May show the OS permission prompt. Returns false if unavailable/denied.
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(RecognizerError error) onError,
  });

  /// The platform's own id for [requested] (ids differ: `ar_SA` vs `ar-SA`),
  /// or null if no matching recognition voice exists.
  Future<String?> resolveLocale(String requested);

  Future<void> listen({
    required String localeId,
    required Duration listenFor,
    required Duration pauseFor,
    required void Function(RecognizerResult result) onResult,
    required void Function(double level) onSoundLevel,
  });

  Future<void> stop();

  Future<void> cancel();
}

/// Text-to-speech, as the engine needs it. The adapter wraps `flutter_tts`.
abstract interface class SpeechSynthesizerPort {
  Future<bool> isLanguageAvailable(String languageTag);

  Future<void> setLanguage(String languageTag);

  /// Registers the platform callbacks (replacing any earlier ones).
  void bind({
    required void Function() onStart,
    required void Function() onComplete,
    required void Function() onCancel,
    required void Function(String message) onError,
  });

  /// Starts speaking [text]. Returns once the request is accepted, not when
  /// speech ends.
  Future<void> speak(String text);

  Future<void> stop();
}

/// The shared OS audio session. The adapter wraps `audio_session`.
abstract interface class AudioSessionPort {
  /// Configures category/mode/focus for conversational speech and listening.
  Future<void> configureForVoice();

  /// Activates or deactivates the session. Returns false if the OS refused
  /// (for example during a phone call).
  Future<bool> setActive({required bool active});

  /// Pause-style interruptions only: true = began, false = ended. Volume
  /// ducking is filtered out by the adapter.
  Stream<bool> get interruptions;

  /// Fires when the output route is lost (headphones unplugged).
  Stream<void> get becomingNoisy;
}

/// Microphone (and, on iOS, speech-recognition) permission.
abstract interface class VoicePermissionPort {
  /// Never prompts.
  Future<VoicePermissionStatus> check();

  /// May prompt. Returns the combined resulting status.
  Future<VoicePermissionStatus> request();
}
