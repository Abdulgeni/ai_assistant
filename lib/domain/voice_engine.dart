import 'package:ai_assistant/domain/entities/value_object.dart';
import 'package:ai_assistant/domain/entities/voice_state.dart';

enum RecognitionStopReason {
  /// Caller asked ([VoiceEngine.stopListening] / [VoiceEngine.cancelListening])
  /// or the engine gated the mic for playback in half-duplex.
  requested,

  /// Platform recognizer timed out (iOS/Android sessions are short). The
  /// controller should restart listening if the session is still active.
  timeout,

  /// Recognizer ended without hearing speech.
  noSpeech,
}

/// Low-level facts reported by a [VoiceEngine].
sealed class VoiceEngineEvent extends ValueObject {
  const VoiceEngineEvent();
}

final class SessionStateChanged extends VoiceEngineEvent {
  const SessionStateChanged(this.state);

  final VoiceSessionState state;

  @override
  List<Object?> get props => <Object?>[state];
}

final class RecognitionPartial extends VoiceEngineEvent {
  const RecognitionPartial(this.text);

  final String text;

  @override
  List<Object?> get props => <Object?>[text];

  @override
  String toString() => 'RecognitionPartial(chars: ${text.length})';
}

final class RecognitionFinal extends VoiceEngineEvent {
  const RecognitionFinal(this.text);

  final String text;

  @override
  List<Object?> get props => <Object?>[text];

  @override
  String toString() => 'RecognitionFinal(chars: ${text.length})';
}

final class RecognitionStopped extends VoiceEngineEvent {
  const RecognitionStopped(this.reason);

  final RecognitionStopReason reason;

  @override
  List<Object?> get props => <Object?>[reason];
}

final class PlaybackStarted extends VoiceEngineEvent {
  const PlaybackStarted();

  @override
  List<Object?> get props => const <Object?>[];
}

/// The speak queue drained naturally.
final class PlaybackFinished extends VoiceEngineEvent {
  const PlaybackFinished();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Playback was cut short by [VoiceEngine.stopSpeaking].
final class PlaybackCancelled extends VoiceEngineEvent {
  const PlaybackCancelled();

  @override
  List<Object?> get props => const <Object?>[];
}

/// User speech detected during playback. Only emitted when
/// [VoiceCapabilities.supportsAutomaticBargeIn] is true. The engine does NOT
/// stop playback itself; the controller must call [VoiceEngine.stopSpeaking]
/// immediately.
final class BargeInDetected extends VoiceEngineEvent {
  const BargeInDetected();

  @override
  List<Object?> get props => const <Object?>[];
}

/// OS-level audio interruption (phone call, other app, route loss).
final class AudioInterruption extends VoiceEngineEvent {
  const AudioInterruption({required this.began});

  final bool began;

  @override
  List<Object?> get props => <Object?>[began];
}

final class EngineFailure extends VoiceEngineEvent {
  const EngineFailure(this.failure);

  final VoiceFailure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}

/// Duplex voice contract (speech recognition + speech synthesis + audio
/// session). Platform adapters live in `data/`; the UI never touches plugins.
///
/// Behavioral contract:
///  * [events] and [audioLevel] are broadcast streams that close on [dispose].
///  * [startSession] throws [VoiceException] if permissions are missing, the
///    audio session cannot be configured, or `config.duplexMode` is
///    [DuplexMode.fullDuplex] while [VoiceCapabilities.supportsFullDuplex] is
///    false (`unsupportedDuplexMode`).
///  * Half-duplex: [speak] while recognition is active first stops recognition
///    (emitting `RecognitionStopped(requested)`); [startListening] while
///    playback is active throws `invalidState`. Callers stop speech first.
///  * [speak] ENQUEUES text (the controller feeds sentence-sized chunks as the
///    LLM streams). It returns once accepted; completion is signalled by
///    [PlaybackFinished]. [stopSpeaking] clears the queue.
///  * [audioLevel] is normalized to 0.0 to 1.0 and emitted at most ~30 Hz while
///    listening or speaking. It stays empty if `!supportsAudioLevel`.
///  * After [dispose], no other method may be called. [dispose] is idempotent
///    and must release every native resource (recognizer, TTS, audio session).
abstract interface class VoiceEngine {
  VoiceCapabilities get capabilities;

  /// Current session state (also announced via [SessionStateChanged]).
  VoiceSessionState get sessionState;

  Stream<VoiceEngineEvent> get events;

  Stream<double> get audioLevel;

  Future<VoicePermissionStatus> checkPermissions();

  /// May show the OS prompt. Returns the resulting status.
  Future<VoicePermissionStatus> requestPermissions();

  Future<VoiceLanguageSupport> checkLanguage({
    required String recognitionLocaleId,
    required String synthesisLocaleTag,
  });

  Future<void> startSession(VoiceSessionConfig config);

  Future<void> endSession();

  /// Starts recognition. Results arrive as [RecognitionPartial] /
  /// [RecognitionFinal] events.
  Future<void> startListening();

  /// Ends recognition gracefully; a [RecognitionFinal] may still be emitted.
  Future<void> stopListening();

  /// Ends recognition and discards any pending result.
  Future<void> cancelListening();

  Future<void> speak(String text);

  Future<void> stopSpeaking();

  Future<void> dispose();
}
