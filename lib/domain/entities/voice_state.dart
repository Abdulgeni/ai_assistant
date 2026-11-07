import 'package:ai_assistant/domain/entities/value_object.dart';

// ---------------------------------------------------------------- failures

enum VoiceFailureCode {
  permissionDenied,
  permissionPermanentlyDenied,
  recognizerUnavailable,
  languageUnavailable,
  audioSessionFailed,

  /// Full duplex requested but [VoiceCapabilities.supportsFullDuplex] is false.
  unsupportedDuplexMode,

  /// Method called in the wrong state (no session, ordering violation).
  invalidState,
  recognitionFailed,
  playbackFailed,
  unknown,
}

final class VoiceFailure extends ValueObject {
  const VoiceFailure({
    required this.code,
    required this.message,
    this.recoverable = true,
  });

  final VoiceFailureCode code;

  /// Developer-facing English; the UI maps [code] to localized text.
  final String message;
  final bool recoverable;

  @override
  List<Object?> get props => <Object?>[code, message, recoverable];
}

/// Thrown by [VoiceEngine] methods when an operation cannot proceed.
final class VoiceException implements Exception {
  const VoiceException(this.failure);

  final VoiceFailure failure;

  @override
  String toString() =>
      'VoiceException(${failure.code.name}: ${failure.message})';
}

// ------------------------------------------------------ config / capability

enum DuplexMode {
  /// Mic is gated while the assistant speaks. Safe without echo cancellation.
  halfDuplex,

  /// Mic stays live during playback. Only valid with confirmed echo
  /// cancellation ([VoiceCapabilities.supportsFullDuplex]).
  fullDuplex,
}

enum VoicePermissionStatus { granted, denied, permanentlyDenied, restricted }

/// What the current platform adapter can safely do.
///
/// v1: iOS reports what the spike verifies; Android reports
/// [VoiceCapabilities.halfDuplexOnly]. A future record-package AEC adapter just
/// reports `supportsFullDuplex: true`.
final class VoiceCapabilities extends ValueObject {
  const VoiceCapabilities({
    required this.supportsFullDuplex,
    required this.supportsAutomaticBargeIn,
    required this.supportsAudioLevel,
  }) : assert(
          !supportsFullDuplex || supportsAutomaticBargeIn,
          'Full duplex requires automatic barge-in support.',
        );

  const VoiceCapabilities.halfDuplexOnly({this.supportsAudioLevel = true})
      : supportsFullDuplex = false,
        supportsAutomaticBargeIn = false;

  /// Mic may stay live during playback (echo cancellation confirmed).
  final bool supportsFullDuplex;

  /// Engine can detect the user speaking over playback by itself. When false
  /// the UI must offer tap-to-interrupt instead.
  final bool supportsAutomaticBargeIn;

  /// [VoiceEngine.audioLevel] emits real values (otherwise it stays empty).
  final bool supportsAudioLevel;

  @override
  List<Object?> get props => <Object?>[
        supportsFullDuplex,
        supportsAutomaticBargeIn,
        supportsAudioLevel,
      ];
}

final class VoiceLanguageSupport extends ValueObject {
  const VoiceLanguageSupport({
    required this.recognition,
    required this.synthesis,
  });

  final bool recognition;
  final bool synthesis;

  @override
  List<Object?> get props => <Object?>[recognition, synthesis];
}

final class VoiceSessionConfig extends ValueObject {
  const VoiceSessionConfig({
    required this.recognitionLocaleId,
    required this.synthesisLocaleTag,
    this.duplexMode = DuplexMode.halfDuplex,
  });

  /// Opaque, platform-specific STT locale id (e.g. `ar_SA` vs `ar-SA`).
  /// Adapters are responsible for normalizing it.
  final String recognitionLocaleId;

  /// TTS language tag (e.g. `ar`).
  final String synthesisLocaleTag;
  final DuplexMode duplexMode;

  @override
  List<Object?> get props =>
      <Object?>[recognitionLocaleId, synthesisLocaleTag, duplexMode];
}

// ------------------------------------------------------------ session state

/// Lifecycle of the audio session. Owned by the [VoiceEngine].
sealed class VoiceSessionState extends ValueObject {
  const VoiceSessionState();
}

final class VoiceSessionIdle extends VoiceSessionState {
  const VoiceSessionIdle();

  @override
  List<Object?> get props => const <Object?>[];
}

final class VoiceSessionPreparing extends VoiceSessionState {
  const VoiceSessionPreparing();

  @override
  List<Object?> get props => const <Object?>[];
}

final class VoiceSessionActive extends VoiceSessionState {
  const VoiceSessionActive({required this.duplexMode});

  final DuplexMode duplexMode;

  @override
  List<Object?> get props => <Object?>[duplexMode];
}

final class VoiceSessionStopping extends VoiceSessionState {
  const VoiceSessionStopping();

  @override
  List<Object?> get props => const <Object?>[];
}

final class VoiceSessionFailed extends VoiceSessionState {
  const VoiceSessionFailed(this.failure);

  final VoiceFailure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}

// --------------------------------------------------------------- turn state

/// What the conversation is doing right now. Owned by the presentation-layer
/// voice controller (only it knows when the LLM is "thinking").
sealed class VoiceTurnState extends ValueObject {
  const VoiceTurnState();
}

/// Session is active but nothing is happening between turns.
final class TurnIdle extends VoiceTurnState {
  const TurnIdle();

  @override
  List<Object?> get props => const <Object?>[];
}

final class TurnListening extends VoiceTurnState {
  const TurnListening({this.partialTranscript = ''});

  final String partialTranscript;

  @override
  List<Object?> get props => <Object?>[partialTranscript];

  @override
  String toString() => 'TurnListening(chars: ${partialTranscript.length})';
}

final class TurnThinking extends VoiceTurnState {
  const TurnThinking({required this.transcript});

  final String transcript;

  @override
  List<Object?> get props => <Object?>[transcript];

  @override
  String toString() => 'TurnThinking(chars: ${transcript.length})';
}

final class TurnSpeaking extends VoiceTurnState {
  const TurnSpeaking();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Transient: the user barged in; playback has stopped and listening restarts.
final class TurnInterrupted extends VoiceTurnState {
  const TurnInterrupted();

  @override
  List<Object?> get props => const <Object?>[];
}
