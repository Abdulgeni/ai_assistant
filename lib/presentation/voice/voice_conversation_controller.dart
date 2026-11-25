import 'dart:async';

import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/core/localization/locale_support.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/voice_state.dart';
import 'package:ai_assistant/domain/voice_engine.dart';
import 'package:ai_assistant/presentation/providers/app_settings_providers.dart';
import 'package:ai_assistant/presentation/providers/chat_notifier.dart';
import 'package:ai_assistant/presentation/providers/chat_state.dart';
import 'package:ai_assistant/presentation/providers/conversation_providers.dart';
import 'package:ai_assistant/presentation/providers/core_providers.dart';
import 'package:ai_assistant/presentation/providers/streaming_buffer.dart';
import 'package:ai_assistant/presentation/voice/speech_text.dart';
import 'package:ai_assistant/presentation/voice/voice_conversation_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final voiceLimitsProvider = Provider<VoiceLimits>((ref) => const VoiceLimits());

/// Recognition and speech language from the UI language.
VoiceSessionConfig voiceConfigFor(Locale locale) =>
    locale.languageCode == 'ar'
        ? const VoiceSessionConfig(
            recognitionLocaleId: 'ar_SA',
            synthesisLocaleTag: 'ar',
          )
        : const VoiceSessionConfig(
            recognitionLocaleId: 'en_US',
            synthesisLocaleTag: 'en',
          );

/// A reply with this many characters and no sentence end is spoken anyway.
const int _maxPendingChars = 220;

/// Runs a spoken conversation: listen, send what was said to the chat, speak
/// the answer sentence by sentence as it streams, then listen again.
///
/// Half-duplex: the microphone is never open while the assistant speaks, so
/// the user interrupts with a TAP (stop the reply, then listen).
///
/// Engine commands are queued and answered asynchronously, and events can
/// arrive late. Rules that keep this correct (each was found by simulation):
///  * A reply is finished only when the chat is done, no speak command is still
///    awaiting commit, AND the engine reports it is not speaking: a stale
///    "finished" from an earlier run can arrive after a newer sentence was queued.
///  * `Stopped(requested)` only counts if THIS controller asked to stop; it is
///    otherwise an echo of its own earlier cancel.
///  * Speak commands carry the session epoch, so ones queued before a teardown
///    cannot corrupt the pending count.
///  * Whenever the controller abandons speech or listening (interrupt, OS
///    interruption) it queues the matching stop BEHIND anything already queued;
///    and it never queues the microphone behind speech that is pending or
///    playing.
class VoiceConversationController extends Notifier<VoiceConversationState> {
  String? _conversationId;
  int _session = 0;
  StreamSubscription<VoiceEngineEvent>? _engineSub;
  ProviderSubscription<ChatState>? _chatSub;
  ProviderSubscription<StreamingBufferState>? _bufferSub;
  final SpeechChunker _chunker = SpeechChunker(maxPending: _maxPendingChars);

  bool _replyActive = false;
  String? _replyId;
  bool _replyComplete = false;
  bool _muted = false;
  bool _speaksReplies = true;
  int _pendingSpeaks = 0;
  int _emptyRestarts = 0;
  int _recognitionFailures = 0;
  bool _stopPending = false;

  VoiceEngine get _engine => ref.read(voiceEngineProvider);

  @override
  VoiceConversationState build() {
    ref.onDispose(() {
      _session++;
      unawaited(_engineSub?.cancel());
      _chatSub?.close();
      _bufferSub?.close();
    });
    return const VoiceConversationState();
  }

  // ------------------------------------------------------------- lifecycle

  /// Opens voice mode for [conversationId]: permissions, language, audio
  /// session, then starts listening. Calling it again after a permission or
  /// failure state retries (and may show the permission prompt again).
  Future<void> start(String conversationId) async {
    if (state.phase == VoicePhase.preparing || state.phase == VoicePhase.active) {
      return;
    }
    _conversationId = conversationId;
    _session++;
    _resetCounters();
    state = const VoiceConversationState(phase: VoicePhase.preparing);

    final VoicePermissionStatus permission =
        await _engine.requestPermissions();
    if (!ref.mounted) return;
    if (permission != VoicePermissionStatus.granted) {
      state = state.copyWith(
        phase: permission == VoicePermissionStatus.permanentlyDenied ||
                permission == VoicePermissionStatus.restricted
            ? VoicePhase.permissionBlocked
            : VoicePhase.permissionDenied,
        failureCode: permission == VoicePermissionStatus.permanentlyDenied ||
                permission == VoicePermissionStatus.restricted
            ? VoiceFailureCode.permissionPermanentlyDenied
            : VoiceFailureCode.permissionDenied,
      );
      return;
    }

    final Locale locale = ref.read(localeProvider) ?? const Locale('ar');
    final VoiceSessionConfig config = voiceConfigFor(locale);
    final VoiceLanguageSupport language = await _engine.checkLanguage(
      recognitionLocaleId: config.recognitionLocaleId,
      synthesisLocaleTag: config.synthesisLocaleTag,
    );
    if (!ref.mounted) return;
    if (!language.recognition) {
      state = state.copyWith(
        phase: VoicePhase.languageUnavailable,
        failureCode: VoiceFailureCode.languageUnavailable,
      );
      return;
    }
    _speaksReplies = language.synthesis;

    _attachEngineListener();

    try {
      await _engine.startSession(config);
    } on VoiceException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: _phaseFor(e.failure.code),
        failureCode: e.failure.code,
      );
      return;
    }
    if (!ref.mounted) return;

    state = state.copyWith(
      phase: VoicePhase.active,
      turn: const TurnIdle(),
      speaksReplies: _speaksReplies,
      clearFailureCode: true,
      clearReplyFailure: true,
    );

    await _beginListening();
  }

  /// Ends voice mode. Stops speaking, stops listening, ends the audio session.
  Future<void> stop() async {
    _session++;
    _chatSub?.close();
    _chatSub = null;
    _bufferSub?.close();
    _bufferSub = null;
    await _engineSub?.cancel();
    _engineSub = null;
    await _safeEngine(() => _engine.stopSpeaking());
    await _safeEngine(() => _engine.endSession());
    if (!ref.mounted) return;
    _resetCounters();
    _conversationId = null;
    state = const VoiceConversationState();
  }

  /// The user tapped the mic while the assistant is speaking: stop the reply
  /// and listen again.
  Future<void> interrupt() async {
    if (!state.isActive) return;
    _stopPending = true;
    await _safeEngine(() => _engine.stopSpeaking());
    _endReplyIfDone();
    _stopPending = false;
    await _beginListening();
  }

  /// Retries after a permission denial by calling [start] again.
  Future<void> retry() async {
    final String? id = _conversationId;
    if (id == null) return;
    state = const VoiceConversationState();
    await start(id);
  }

  // ------------------------------------------------------------- internals

  void _attachEngineListener() {
    _engineSub ??= _engine.events.listen(_onEngineEvent);
  }

  Future<void> _beginListening() async {
    if (!state.isActive) return;
    // Never queue the mic behind speech that is pending or playing.
    if (_engine.isSpeaking || _pendingSpeaks > 0) {
      await _safeEngine(() => _engine.stopSpeaking());
    }
    if (!ref.mounted || !state.isActive) return;
    await _safeEngine(() => _engine.startListening());
    if (!ref.mounted || !state.isActive) return;
    state = state.copyWith(turn: const TurnListening());
  }

  void _onEngineEvent(VoiceEngineEvent event) {
    if (!ref.mounted) return;
    switch (event) {
      case SessionStateChanged(:final state):
        if (state is VoiceSessionFailed && this.state.isActive) {
          this.state = this.state.copyWith(
            phase: VoicePhase.failed,
            failureCode: state.failure.code,
            turn: const TurnIdle(),
          );
        }
      case RecognitionPartial():
        break;
      case RecognitionFinal(:final text):
        if (!this.state.isActive || this.state.turn is! TurnListening) return;
        _emptyRestarts = 0;
        _recognitionFailures = 0;
        this.state = this.state.copyWith(turn: const TurnThinking());
        _sendTranscript(text);
      case RecognitionStopped(:final reason):
        _onRecognitionStopped(reason);
      case PlaybackStarted():
        break;
      case PlaybackFinished():
        _onPlaybackEnded();
      case PlaybackCancelled():
        _onPlaybackEnded();
      case AudioInterruption(began: true):
        _onAudioInterruption();
      case AudioInterruption(began: false):
        break;
      case EngineFailure(:final failure):
        _onEngineFailure(failure);
      case BargeInDetected():
        // Half-duplex only: no automatic barge-in.
        break;
    }
  }

  void _onRecognitionStopped(RecognitionStopReason reason) {
    if (!state.isActive) return;
    switch (reason) {
      case RecognitionStopReason.requested:
        if (_stopPending) return;
        // Stale echo of an earlier cancel: only act when nothing else is
        // happening and the user is waiting.
        if (state.turn is! TurnListening) return;
        _beginListening();
      case RecognitionStopReason.timeout:
      case RecognitionStopReason.noSpeech:
        _emptyRestarts++;
        if (_emptyRestarts > ref.read(voiceLimitsProvider).maxEmptyRestarts) {
          state = state.copyWith(turn: const TurnIdle());
          return;
        }
        _beginListening();
    }
  }

  void _onPlaybackEnded() {
    if (!state.isActive) return;
    if (state.turn is! TurnSpeaking) return;
    _endReplyIfDone();
  }

  void _onAudioInterruption() {
    if (!state.isActive) return;
    if (state.turn is TurnListening || state.turn is TurnThinking) {
      state = state.copyWith(turn: const TurnIdle());
    } else if (state.turn is TurnSpeaking) {
      state = state.copyWith(turn: const TurnInterrupted());
    }
  }

  void _onEngineFailure(VoiceFailure failure) {
    if (!state.isActive) return;
    _recognitionFailures++;
    if (_recognitionFailures > ref.read(voiceLimitsProvider).maxRecognitionFailures) {
      state = state.copyWith(
        phase: _phaseFor(failure.code),
        failureCode: failure.code,
        turn: const TurnIdle(),
      );
      return;
    }
    _beginListening();
  }

  void _endReplyIfDone() {
    if (!_replyActive) return;
    if (!_replyComplete) return;
    if (_pendingSpeaks > 0) return;
    if (_engine.isSpeaking) return;
    _replyActive = false;
    _replyId = null;
    if (!ref.mounted) return;
    if (state.turn is! TurnSpeaking && state.turn is! TurnInterrupted) return;
    state = state.copyWith(turn: const TurnIdle());
    _beginListening();
  }

  void _sendTranscript(String transcript) {
    final String? id = _conversationId;
    if (id == null) return;
    final ChatNotifier notifier =
        ref.read(chatNotifierProvider(id).notifier);
    if (!notifier.send(transcript)) {
      if (!ref.mounted) return;
      state = state.copyWith(chatBusy: true, turn: const TurnIdle());
      return;
    }
    _replyActive = true;
    _replyComplete = false;
    _replyId = null;
    _pendingSpeaks = 0;
    _chunker.reset();
    _chatSub?.close();
    _bufferSub?.close();
    _chatSub = ref.listenManual<ChatState>(
      chatNotifierProvider(id),
      (previous, next) => _onChatChanged(id, next),
    );
    _bufferSub = ref.listenManual<StreamingBufferState>(
      streamingBufferProvider,
      (previous, next) => _onBufferChanged(next),
    );
  }

  void _onChatChanged(String conversationId, ChatState chat) {
    if (!_replyActive) return;
    if (chat.isStreaming) {
      if (state.turn is! TurnSpeaking && state.turn is! TurnThinking) {
        state = state.copyWith(turn: const TurnThinking());
      }
      return;
    }
    _replyComplete = true;
    // Find the assistant message for this reply.
    final String? targetId = _replyId;
    if (targetId != null) {
      for (final ChatMessage m in chat.messages) {
        if (m.id == targetId) {
          if (m.status == MessageStatus.failed) {
            state = state.copyWith(
              replyFailure: chat.failure?.code,
              turn: const TurnIdle(),
            );
            _replyActive = false;
            _replyId = null;
            _beginListening();
            return;
          }
          break;
        }
      }
    }
    _endReplyIfDone();
  }

  void _onBufferChanged(StreamingBufferState buffer) {
    if (!_replyActive) return;
    final String? id = _replyId ?? buffer.messageId;
    if (id == null) return;
    if (buffer.messageId != id) return;
    _replyId = id;
    if (buffer.text.isEmpty) return;
    if (_speaksReplies && !_muted) {
      _speakPending(buffer.text);
    }
    if (state.turn is! TurnSpeaking) {
      state = state.copyWith(turn: const TurnSpeaking());
    }
  }

  Future<void> _speakPending(String text) async {
    final List<String> sentences = _chunker.add(text);
    for (final String sentence in sentences) {
      if (!ref.mounted || !state.isActive) return;
      _pendingSpeaks++;
      final int epoch = _session;
      unawaited(
        _engine.speak(sentence).then((_) {
          if (epoch == _session) _pendingSpeaks--;
        }).catchError((Object _) {
          if (epoch == _session) _pendingSpeaks--;
        }),
      );
    }
  }

  PhaseEnumHelpers _phaseFor(VoiceFailureCode code) {
    switch (code) {
      case VoiceFailureCode.permissionDenied:
        return VoicePhase.permissionDenied;
      case VoiceFailureCode.permissionPermanentlyDenied:
        return VoicePhase.permissionBlocked;
      case VoiceFailureCode.languageUnavailable:
        return VoicePhase.languageUnavailable;
      default:
        return VoicePhase.failed;
    }
  }

  void _resetCounters() {
    _replyActive = false;
    _replyComplete = false;
    _replyId = null;
    _muted = false;
    _pendingSpeaks = 0;
    _emptyRestarts = 0;
    _recognitionFailures = 0;
    _stopPending = false;
    _chunker.reset();
  }

  Future<void> _safeEngine(Future<void> Function() action) async {
    try {
      await action();
    } on VoiceException {
      // Best-effort: a failure here must not break the controller.
    }
  }
}

typedef PhaseEnumHelpers = VoicePhase;

final voiceConversationControllerProvider =
    NotifierProvider<VoiceConversationController, VoiceConversationState>(
  VoiceConversationController.new,
);
