import 'dart:async';
import 'dart:collection';

import 'package:ai_assistant/data/voice/sound_level_normalizer.dart';
import 'package:ai_assistant/data/voice/voice_ports.dart';
import 'package:ai_assistant/data/voice/voice_text_utils.dart';
import 'package:ai_assistant/domain/entities/voice_state.dart';
import 'package:ai_assistant/domain/voice_engine.dart';

/// [VoiceEngine] over platform speech recognition, speech synthesis, and the OS
/// audio session.
///
/// HALF-DUPLEX ONLY. Neither `speech_to_text` nor `flutter_tts` exposes echo
/// cancellation, so the microphone and the speaker are never active together:
/// speaking cancels listening, and listening is refused while speaking.
/// Barge-in is therefore a tap, not automatic detection.
///
/// Concurrency: public commands run one at a time. Each command changes its
/// state synchronously BEFORE awaiting any port call, and platform callbacks do
/// only synchronous state work, so a callback arriving mid-command always sees
/// consistent state.
///
/// Platform callbacks can be late or out of order. Defenses:
///  * recognition results carry a per-listen token; stale ones are dropped;
///  * an end-of-listen status counts only after that listen's own `listening`
///    status (a stale `done` from a cancelled listen arrives before it);
///  * TTS completion and cancel callbacks count only after the current chunk's
///    start callback (stale echoes of our own `stop()` arrive before it);
///  * the engine consults [SpeechRecognizerPort.isListening] rather than its
///    own flag, because the recognizer can stay live briefly after a final
///    result.
/// Known limit: a stale end-status arriving AFTER the new listen's `listening`
/// status cannot be told apart and ends that listen early.
final class PlatformVoiceEngine implements VoiceEngine {
  PlatformVoiceEngine({
    required SpeechRecognizerPort recognizer,
    required SpeechSynthesizerPort synthesizer,
    required AudioSessionPort audioSession,
    required VoicePermissionPort permissions,
    DateTime Function()? clock,
    this.listenFor = const Duration(seconds: 60),
    this.pauseFor = const Duration(seconds: 2),
    this.startTimeout = const Duration(seconds: 5),
    this.maxChunkLength = 3000,
  })  : _recognizer = recognizer,
        _synthesizer = synthesizer,
        _audio = audioSession,
        _permissions = permissions,
        _clock = clock ?? DateTime.now;

  /// Longest single recognition (platform caps are around a minute).
  final Duration listenFor;

  /// Silence that ends an utterance.
  final Duration pauseFor;

  /// How long a chunk may take to begin playing before it counts as failed.
  final Duration startTimeout;

  final int maxChunkLength;

  static const Duration _timeoutMargin = Duration(seconds: 2);
  static const Duration _levelInterval = Duration(milliseconds: 33);

  final SpeechRecognizerPort _recognizer;
  final SpeechSynthesizerPort _synthesizer;
  final AudioSessionPort _audio;
  final VoicePermissionPort _permissions;
  final DateTime Function() _clock;

  final StreamController<VoiceEngineEvent> _events =
      StreamController<VoiceEngineEvent>.broadcast();
  final StreamController<double> _levels = StreamController<double>.broadcast();
  final SoundLevelNormalizer _normalizer = SoundLevelNormalizer();

  VoiceSessionState _sessionState = const VoiceSessionIdle();
  bool _disposed = false;
  String? _resolvedLocaleId;
  bool _audioActive = false;
  StreamSubscription<bool>? _interruptionSub;
  StreamSubscription<void>? _noisySub;
  Future<void> _serial = Future<void>.value();

  // Listening.
  bool _listening = false;
  int _listenToken = 0;
  bool _stopRequested = false;
  bool _finalDelivered = false;
  String _lastPartial = '';
  bool _sawListeningStatus = false;
  DateTime _listenStartedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastLevelAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Playback.
  final Queue<String> _queue = Queue<String>();
  bool _speaking = false;
  bool _chunkStarted = false;
  bool _runOpen = false;
  bool _runStarted = false;
  int _utteranceToken = 0;
  Timer? _startWatchdog;

  // ------------------------------------------------------------ properties

  @override
  VoiceCapabilities get capabilities =>
      const VoiceCapabilities.halfDuplexOnly();

  @override
  VoiceSessionState get sessionState => _sessionState;

  @override
  Stream<VoiceEngineEvent> get events => _events.stream;

  @override
  Stream<double> get audioLevel => _levels.stream;

  // ----------------------------------------------------------- permissions

  @override
  Future<VoicePermissionStatus> checkPermissions() => _permissions.check();

  @override
  Future<VoicePermissionStatus> requestPermissions() => _permissions.request();

  @override
  Future<VoiceLanguageSupport> checkLanguage({
    required String recognitionLocaleId,
    required String synthesisLocaleTag,
  }) async {
    var recognition = false;
    var synthesis = false;
    try {
      // Initializing the recognizer can show the OS permission prompt, so only
      // touch it once permission already exists.
      if (await _permissions.check() == VoicePermissionStatus.granted) {
        recognition = await _recognizer.resolveLocale(recognitionLocaleId) != null;
      }
    } on Object {
      recognition = false;
    }
    try {
      synthesis = await _synthesizer.isLanguageAvailable(synthesisLocaleTag);
    } on Object {
      synthesis = false;
    }
    return VoiceLanguageSupport(recognition: recognition, synthesis: synthesis);
  }

  // --------------------------------------------------------------- session

  @override
  Future<void> startSession(VoiceSessionConfig config) =>
      _enqueue<void>(() async {
        final VoiceSessionState current = _sessionState;
        if (_disposed ||
            !(current is VoiceSessionIdle || current is VoiceSessionFailed)) {
          throw _error(
            VoiceFailureCode.invalidState,
            'A voice session is already active or changing state.',
          );
        }
        if (config.duplexMode == DuplexMode.fullDuplex &&
            !capabilities.supportsFullDuplex) {
          throw _error(
            VoiceFailureCode.unsupportedDuplexMode,
            'Full duplex is not supported: no echo cancellation is available.',
          );
        }

        _setSession(const VoiceSessionPreparing());
        try {
          await _prepare(config);
          _setSession(
            const VoiceSessionActive(duplexMode: DuplexMode.halfDuplex),
          );
        } on VoiceException catch (error) {
          await _releaseAudio();
          _setSession(VoiceSessionFailed(error.failure));
          rethrow;
        } on Object catch (error) {
          await _releaseAudio();
          final VoiceFailure failure = VoiceFailure(
            code: VoiceFailureCode.unknown,
            message: 'Voice setup failed (${error.runtimeType}).',
          );
          _setSession(VoiceSessionFailed(failure));
          throw VoiceException(failure);
        }
      });

  Future<void> _prepare(VoiceSessionConfig config) async {
    final VoicePermissionStatus permission = await _permissions.check();
    if (permission != VoicePermissionStatus.granted) {
      final bool permanent = permission == VoicePermissionStatus.permanentlyDenied ||
          permission == VoicePermissionStatus.restricted;
      throw _error(
        permanent
            ? VoiceFailureCode.permissionPermanentlyDenied
            : VoiceFailureCode.permissionDenied,
        'Microphone or speech permission is not granted.',
        recoverable: !permanent,
      );
    }

    await _audio.configureForVoice();
    if (!await _audio.setActive(active: true)) {
      throw _error(
        VoiceFailureCode.audioSessionFailed,
        'The audio session could not be activated (another app may hold it).',
      );
    }
    _audioActive = true;

    final bool initialized = await _recognizer.initialize(
      onStatus: _onStatus,
      onError: _onRecognizerError,
    );
    if (!initialized) {
      throw _error(
        VoiceFailureCode.recognizerUnavailable,
        'Speech recognition is unavailable on this device.',
      );
    }
    final String? locale =
        await _recognizer.resolveLocale(config.recognitionLocaleId);
    if (locale == null) {
      throw _error(
        VoiceFailureCode.languageUnavailable,
        'No recognition voice for ${config.recognitionLocaleId}.',
      );
    }

    // A missing speech voice is not fatal: the device default is used.
    if (await _synthesizer.isLanguageAvailable(config.synthesisLocaleTag)) {
      await _synthesizer.setLanguage(config.synthesisLocaleTag);
    }
    _synthesizer.bind(
      onStart: _onSynthStart,
      onComplete: _onSynthComplete,
      onCancel: _onSynthCancel,
      onError: _onSynthError,
    );

    _resolvedLocaleId = locale;
    _normalizer.reset();
    _interruptionSub = _audio.interruptions.listen(_onInterruption);
    _noisySub = _audio.becomingNoisy.listen((_) => _onBecomingNoisy());
  }

  @override
  Future<void> endSession() => _enqueue<void>(_endSessionImpl);

  Future<void> _endSessionImpl() async {
    if (_disposed || _sessionState is VoiceSessionIdle) return;
    _setSession(const VoiceSessionStopping());
    _cancelListenState(emit: false);
    _dropPlaybackState();
    await _safe(_recognizer.cancel);
    await _safe(_synthesizer.stop);
    await _releaseAudio();
    _setSession(const VoiceSessionIdle());
  }

  Future<void> _releaseAudio() async {
    await _interruptionSub?.cancel();
    _interruptionSub = null;
    await _noisySub?.cancel();
    _noisySub = null;
    if (_audioActive) {
      _audioActive = false;
      await _safe(() async {
        await _audio.setActive(active: false);
      });
    }
  }

  @override
  Future<void> dispose() => _enqueue<void>(() async {
        if (_disposed) return;
        await _endSessionImpl();
        _disposed = true;
        await _events.close();
        await _levels.close();
      });

  // ------------------------------------------------------------- listening

  @override
  Future<void> startListening() => _enqueue<void>(() async {
        _requireActive();
        if (_listening) return;
        if (_speaking || _queue.isNotEmpty) {
          throw _error(
            VoiceFailureCode.invalidState,
            'Half-duplex: stop speaking before listening.',
          );
        }

        final int token = ++_listenToken;
        _listening = true;
        _stopRequested = false;
        _finalDelivered = false;
        _lastPartial = '';
        _sawListeningStatus = false;
        _listenStartedAt = _clock();
        _normalizer.reset();

        try {
          // The platform may still be live from the previous utterance.
          if (_recognizer.isListening) await _recognizer.cancel();
          if (token != _listenToken || !_listening) return; // cancelled meanwhile
          await _recognizer.listen(
            localeId: _resolvedLocaleId!,
            listenFor: listenFor,
            pauseFor: pauseFor,
            onResult: (RecognizerResult result) => _onResult(token, result),
            onSoundLevel: (double level) => _onSoundLevel(token, level),
          );
        } on Object catch (error) {
          if (token == _listenToken) _listening = false;
          throw _error(
            VoiceFailureCode.recognitionFailed,
            'Could not start listening (${error.runtimeType}).',
          );
        }
      });

  @override
  Future<void> stopListening() => _enqueue<void>(() async {
        if (!_listening) return;
        _stopRequested = true;
        await _safe(_recognizer.stop);
      });

  @override
  Future<void> cancelListening() => _enqueue<void>(() async {
        final bool wasLive = _listening || _recognizer.isListening;
        _cancelListenState(emit: true);
        if (wasLive) await _safe(_recognizer.cancel);
      });

  void _cancelListenState({required bool emit}) {
    if (!_listening) return;
    _listening = false;
    _listenToken++;
    if (emit) _emit(const RecognitionStopped(RecognitionStopReason.requested));
  }

  void _onResult(int token, RecognizerResult result) {
    if (_disposed || token != _listenToken || !_listening) return;
    if (result.isFinal) {
      if (_finalDelivered || result.text.trim().isEmpty) return;
      _finalDelivered = true;
      _listening = false;
      _emit(RecognitionFinal(result.text));
      unawaited(_safe(_recognizer.cancel));
    } else {
      _lastPartial = result.text;
      _emit(RecognitionPartial(result.text));
    }
  }

  void _onStatus(String status) {
    if (_disposed || !_listening) return;
    if (status == 'listening') {
      _sawListeningStatus = true;
      return;
    }
    if ((status == 'done' || status == 'notListening') && _sawListeningStatus) {
      _endListenFromPlatform();
    }
  }

  void _endListenFromPlatform() {
    _listening = false;
    unawaited(_safe(_recognizer.cancel));
    if (_lastPartial.trim().isNotEmpty) {
      // Ended without a final result: keep what was heard.
      _finalDelivered = true;
      _emit(RecognitionFinal(_lastPartial));
      return;
    }
    final Duration elapsed = _clock().difference(_listenStartedAt);
    final RecognitionStopReason reason = _stopRequested
        ? RecognitionStopReason.requested
        : (elapsed >= listenFor - _timeoutMargin
            ? RecognitionStopReason.timeout
            : RecognitionStopReason.noSpeech);
    _emit(RecognitionStopped(reason));
  }

  void _onRecognizerError(RecognizerError error) {
    if (_disposed || !_listening) return;
    _listening = false;
    unawaited(_safe(_recognizer.cancel));
    switch (mapRecognizerError(error.message)) {
      case RecognizerErrorKind.noSpeech:
        if (_lastPartial.trim().isNotEmpty) {
          _finalDelivered = true;
          _emit(RecognitionFinal(_lastPartial));
        } else {
          _emit(const RecognitionStopped(RecognitionStopReason.noSpeech));
        }
      case RecognizerErrorKind.permission:
        _emitFailure(VoiceFailureCode.permissionDenied, 'Permission was revoked.');
      case RecognizerErrorKind.busy:
        _emitFailure(
          VoiceFailureCode.recognizerUnavailable,
          'The recognizer is busy.',
        );
      case RecognizerErrorKind.language:
        _emitFailure(
          VoiceFailureCode.languageUnavailable,
          'The recognition language is unavailable.',
        );
      case RecognizerErrorKind.other:
        _emitFailure(
          VoiceFailureCode.recognitionFailed,
          'Recognition failed.',
          recoverable: !error.permanent,
        );
    }
  }

  void _onSoundLevel(int token, double level) {
    if (_disposed || token != _listenToken || !_listening || _levels.isClosed) {
      return;
    }
    final DateTime now = _clock();
    if (now.difference(_lastLevelAt) < _levelInterval) return;
    _lastLevelAt = now;
    _levels.add(_normalizer.add(level));
  }

  // -------------------------------------------------------------- playback

  @override
  Future<void> speak(String text) => _enqueue<void>(() async {
        _requireActive();
        final List<String> chunks =
            splitForSynthesis(text, maxLength: maxChunkLength);
        if (chunks.isEmpty) return;

        // Half-duplex: the microphone must be off before anything is spoken.
        final bool wasListening = _listening;
        _cancelListenState(emit: true);
        if (wasListening || _recognizer.isListening) {
          await _safe(_recognizer.cancel);
        }

        if (!_runOpen) {
          _runOpen = true;
          _runStarted = false;
        }
        _queue.addAll(chunks);
        if (!_speaking) await _speakNext();
      });

  Future<void> _speakNext() async {
    if (_queue.isEmpty) {
      _finishRun();
      return;
    }
    final String chunk = _queue.removeFirst();
    _speaking = true;
    _chunkStarted = false;
    final int token = ++_utteranceToken;
    _startWatchdog?.cancel();
    _startWatchdog = Timer(startTimeout, () => _onStartTimeout(token));
    try {
      await _synthesizer.speak(chunk);
    } on Object {
      if (token == _utteranceToken && _speaking) _failPlayback();
    }
  }

  void _onSynthStart() {
    if (_disposed || !_speaking) return;
    _chunkStarted = true;
    _startWatchdog?.cancel();
    _startWatchdog = null;
    if (!_runStarted) {
      _runStarted = true;
      _emit(const PlaybackStarted());
    }
  }

  void _onSynthComplete() {
    // Ignored before this chunk's start: a stale echo of an earlier utterance.
    if (_disposed || !_speaking || !_chunkStarted) return;
    _speaking = false;
    unawaited(_speakNext());
  }

  void _onSynthCancel() {
    // We always clear our own state before stopping the synthesizer, so a cancel
    // for a STARTED chunk while we still think we are speaking came from the OS
    // (e.g. another app took audio focus): end the run instead of hanging.
    // Before the chunk's start it is a stale echo of our own stop(): ignore.
    if (_disposed || !_speaking || !_chunkStarted) return;
    _dropPlaybackState();
  }

  void _onSynthError(String message) {
    if (_disposed || !_speaking) return;
    _failPlayback();
  }

  void _onStartTimeout(int token) {
    if (_disposed || token != _utteranceToken || !_speaking || _chunkStarted) {
      return;
    }
    _failPlayback();
  }

  void _failPlayback() {
    _dropPlaybackStateSilently();
    unawaited(_safe(_synthesizer.stop));
    _emitFailure(VoiceFailureCode.playbackFailed, 'Speech playback failed.');
    _endRun(const PlaybackCancelled());
  }

  @override
  Future<void> stopSpeaking() => _enqueue<void>(() async {
        if (!(_speaking || _queue.isNotEmpty || _runOpen)) return;
        _dropPlaybackState();
        await _safe(_synthesizer.stop);
      });

  /// Clears all playback state synchronously, then reports the end of the run.
  void _dropPlaybackState() {
    final bool hadRun = _runOpen;
    _dropPlaybackStateSilently();
    if (hadRun) _endRun(const PlaybackCancelled());
  }

  void _dropPlaybackStateSilently() {
    _queue.clear();
    _speaking = false;
    _chunkStarted = false;
    _startWatchdog?.cancel();
    _startWatchdog = null;
    _utteranceToken++;
  }

  void _finishRun() {
    if (_runOpen) _endRun(const PlaybackFinished());
  }

  void _endRun(VoiceEngineEvent terminal) {
    if (!_runOpen) return;
    _runOpen = false;
    _runStarted = false;
    _emit(terminal);
  }

  // --------------------------------------------------------- interruptions

  void _onInterruption(bool began) {
    if (_disposed || _sessionState is! VoiceSessionActive) return;
    if (began) {
      _cancelListenState(emit: true);
      _dropPlaybackState();
      unawaited(_safe(_recognizer.cancel));
      unawaited(_safe(_synthesizer.stop));
      _emit(const AudioInterruption(began: true));
    } else {
      _emit(const AudioInterruption(began: false));
      // Take the audio session back, and re-assert our configuration in case
      // another plugin changed it while we were interrupted.
      unawaited(
        _safe(() async {
          await _audio.configureForVoice();
          await _audio.setActive(active: true);
        }),
      );
    }
  }

  void _onBecomingNoisy() {
    if (_disposed || _sessionState is! VoiceSessionActive) return;
    _dropPlaybackState();
    unawaited(_safe(_synthesizer.stop));
  }

  // --------------------------------------------------------------- helpers

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final Completer<T> completer = Completer<T>();
    _serial = _serial.then((_) async {
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _requireActive() {
    if (_disposed || _sessionState is! VoiceSessionActive) {
      throw _error(
        VoiceFailureCode.invalidState,
        'No active voice session.',
      );
    }
  }

  VoiceException _error(
    VoiceFailureCode code,
    String message, {
    bool recoverable = true,
  }) =>
      VoiceException(
        VoiceFailure(code: code, message: message, recoverable: recoverable),
      );

  /// Best-effort platform call: a failing plugin must never break teardown.
  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // Intentionally ignored.
    }
  }

  void _setSession(VoiceSessionState state) {
    _sessionState = state;
    _emit(SessionStateChanged(state));
  }

  void _emitFailure(
    VoiceFailureCode code,
    String message, {
    bool recoverable = true,
  }) {
    _emit(
      EngineFailure(
        VoiceFailure(code: code, message: message, recoverable: recoverable),
      ),
    );
  }

  void _emit(VoiceEngineEvent event) {
    if (!_disposed && !_events.isClosed) _events.add(event);
  }
}
