import 'package:ai_assistant/domain/entities/stream_event.dart';
import 'package:ai_assistant/domain/entities/value_object.dart';
import 'package:ai_assistant/domain/entities/voice_state.dart';

enum VoicePhase {
  /// Voice mode is closed.
  off,

  /// Checking permissions and starting the audio session.
  preparing,

  /// The user declined; asking again may show the OS prompt.
  permissionDenied,

  /// Declined permanently (or restricted); only system settings can fix it.
  permissionBlocked,

  /// No recognition voice for the chosen language on this device.
  languageUnavailable,

  /// Ready: [VoiceConversationState.turn] says what is happening.
  active,

  /// Voice could not start or died; see [VoiceConversationState.failureCode].
  failed,
}

/// Everything the voice screen renders, other than the live audio level (which
/// the UI reads straight from the engine).
final class VoiceConversationState extends ValueObject {
  const VoiceConversationState({
    this.phase = VoicePhase.off,
    this.turn = const TurnIdle(),
    this.failureCode,
    this.replyFailure,
    this.speaksReplies = true,
    this.chatBusy = false,
  });

  final VoicePhase phase;

  /// Listening, thinking, speaking, interrupted, or idle (waiting for a tap).
  /// Always [TurnIdle] unless [phase] is [VoicePhase.active].
  final VoiceTurnState turn;

  /// Why voice failed or a turn could not continue (UI maps it to text).
  final VoiceFailureCode? failureCode;

  /// Why the last spoken-to reply failed (UI maps it to text).
  final StreamFailureCode? replyFailure;

  /// False when the device has no speech voice for the language: replies appear
  /// as text only.
  final bool speaksReplies;

  /// The last transcript could not be sent: another chat is answering.
  final bool chatBusy;

  bool get isActive => phase == VoicePhase.active;

  VoiceConversationState copyWith({
    VoicePhase? phase,
    VoiceTurnState? turn,
    VoiceFailureCode? failureCode,
    bool clearFailureCode = false,
    StreamFailureCode? replyFailure,
    bool clearReplyFailure = false,
    bool? speaksReplies,
    bool? chatBusy,
  }) =>
      VoiceConversationState(
        phase: phase ?? this.phase,
        turn: turn ?? this.turn,
        failureCode: clearFailureCode ? null : (failureCode ?? this.failureCode),
        replyFailure:
            clearReplyFailure ? null : (replyFailure ?? this.replyFailure),
        speaksReplies: speaksReplies ?? this.speaksReplies,
        chatBusy: chatBusy ?? this.chatBusy,
      );

  @override
  List<Object?> get props => <Object?>[
        phase,
        turn,
        failureCode,
        replyFailure,
        speaksReplies,
        chatBusy,
      ];
}

/// Limits that keep voice mode from looping or holding the microphone open.
final class VoiceLimits {
  const VoiceLimits({this.maxEmptyRestarts = 3, this.maxRecognitionFailures = 2});

  /// Consecutive "heard nothing" rounds before the mic is released and the user
  /// must tap to talk again (saves battery and keeps the mic from being open
  /// indefinitely).
  final int maxEmptyRestarts;

  /// Consecutive recognizer failures retried automatically.
  final int maxRecognitionFailures;
}
