import 'dart:async';
import 'dart:math';

import 'package:ai_assistant/data/repositories/voice_repository_impl.dart';
import 'package:ai_assistant/domain/entities/voice_state.dart';
import 'package:ai_assistant/domain/voice_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_voice_ports.dart';

const VoiceSessionConfig _config = VoiceSessionConfig(
  recognitionLocaleId: 'ar_SA',
  synthesisLocaleTag: 'ar',
);

class _Rig {
  _Rig({Duration startTimeout = const Duration(seconds: 5), int maxChunk = 3000}) {
    engine = PlatformVoiceEngine(
      recognizer: rec,
      synthesizer: synth,
      audioSession: audio,
      permissions: perms,
      clock: clock.call,
      startTimeout: startTimeout,
      maxChunkLength: maxChunk,
    );
    eventSub = engine.events.listen(events.add);
    levelSub = engine.audioLevel.listen(levels.add);
    addTearDown(() async {
      await eventSub.cancel();
      await levelSub.cancel();
    });
  }

  final FakeRecognizer rec = FakeRecognizer();
  final FakeSynthesizer synth = FakeSynthesizer();
  final FakeAudioSession audio = FakeAudioSession();
  final FakePermissions perms = FakePermissions();
  final FakeClock clock = FakeClock();
  late final PlatformVoiceEngine engine;
  late final StreamSubscription<VoiceEngineEvent> eventSub;
  late final StreamSubscription<double> levelSub;
  final List<VoiceEngineEvent> events = <VoiceEngineEvent>[];
  final List<double> levels = <double>[];

  Future<void> pump() => pumpEventQueue();

  Future<void> start() async {
    await engine.startSession(_config);
    await pump();
  }

  Future<void> listen() async {
    await engine.startListening();
    rec.status('listening');
    await pump();
  }

  Future<void> speak(String text) async {
    await engine.speak(text);
    synth.start();
    await pump();
  }

  List<VoiceEngineEvent> get playbackEvents => events
      .where(
        (VoiceEngineEvent e) =>
            e is PlaybackStarted || e is PlaybackFinished || e is PlaybackCancelled,
      )
      .toList();

  Future<VoiceException> failureOf(Future<void> Function() action) async {
    try {
      await action();
    } on VoiceException catch (e) {
      return e;
    }
    fail('expected a VoiceException');
  }
}

void main() {
  group('session', () {
    test('starts: configures and activates audio, reports Preparing then Active',
        () async {
      final _Rig rig = _Rig();
      await rig.start();
      expect(rig.engine.sessionState, isA<VoiceSessionActive>());
      expect(
        rig.events.whereType<SessionStateChanged>().map((SessionStateChanged e) => e.state),
        <VoiceSessionState>[
          const VoiceSessionPreparing(),
          const VoiceSessionActive(duplexMode: DuplexMode.halfDuplex),
        ],
      );
      expect(rig.audio.configureCalls, 1);
      expect(rig.audio.active, isTrue);
    });

    test('reports half-duplex-only capabilities', () {
      final _Rig rig = _Rig();
      expect(rig.engine.capabilities, const VoiceCapabilities.halfDuplexOnly());
      expect(rig.engine.capabilities.supportsFullDuplex, isFalse);
      expect(rig.engine.capabilities.supportsAutomaticBargeIn, isFalse);
    });

    test('refuses full duplex without touching any state', () async {
      final _Rig rig = _Rig();
      final VoiceException error = await rig.failureOf(
        () => rig.engine.startSession(
          const VoiceSessionConfig(
            recognitionLocaleId: 'ar_SA',
            synthesisLocaleTag: 'ar',
            duplexMode: DuplexMode.fullDuplex,
          ),
        ),
      );
      expect(error.failure.code, VoiceFailureCode.unsupportedDuplexMode);
      expect(rig.engine.sessionState, isA<VoiceSessionIdle>());
      expect(rig.events, isEmpty);
    });

    test('a denied permission fails the session, and a retry can succeed',
        () async {
      final _Rig rig = _Rig();
      rig.perms.status = VoicePermissionStatus.denied;
      final VoiceException error =
          await rig.failureOf(() => rig.engine.startSession(_config));
      expect(error.failure.code, VoiceFailureCode.permissionDenied);
      expect(error.failure.recoverable, isTrue);
      expect(rig.engine.sessionState, isA<VoiceSessionFailed>());

      rig.perms.status = VoicePermissionStatus.granted;
      await rig.engine.startSession(_config);
      expect(rig.engine.sessionState, isA<VoiceSessionActive>());
    });

    test('permanently denied and restricted are not recoverable in-app', () async {
      for (final VoicePermissionStatus status in <VoicePermissionStatus>[
        VoicePermissionStatus.permanentlyDenied,
        VoicePermissionStatus.restricted,
      ]) {
        final _Rig rig = _Rig();
        rig.perms.status = status;
        final VoiceException error =
            await rig.failureOf(() => rig.engine.startSession(_config));
        expect(error.failure.code, VoiceFailureCode.permissionPermanentlyDenied);
        expect(error.failure.recoverable, isFalse);
      }
    });

    test('each setup failure maps to its own code and releases audio', () async {
      final Map<VoiceFailureCode, void Function(_Rig)> cases =
          <VoiceFailureCode, void Function(_Rig)>{
        VoiceFailureCode.audioSessionFailed: (_Rig r) => r.audio.activateOk = false,
        VoiceFailureCode.recognizerUnavailable: (_Rig r) => r.rec.initOk = false,
        VoiceFailureCode.languageUnavailable: (_Rig r) => r.rec.resolved = null,
      };
      for (final MapEntry<VoiceFailureCode, void Function(_Rig)> c in cases.entries) {
        final _Rig rig = _Rig();
        c.value(rig);
        final VoiceException error =
            await rig.failureOf(() => rig.engine.startSession(_config));
        expect(error.failure.code, c.key, reason: c.key.name);
        expect(rig.audio.active, isFalse);
        expect(rig.engine.sessionState, isA<VoiceSessionFailed>());
      }
    });

    test('a missing speech voice is not fatal', () async {
      final _Rig rig = _Rig();
      rig.synth.languageAvailable = false;
      await rig.start();
      expect(rig.engine.sessionState, isA<VoiceSessionActive>());
      expect(rig.synth.languagesSet, isEmpty);
    });

    test('starting twice is refused', () async {
      final _Rig rig = _Rig();
      await rig.start();
      final VoiceException error =
          await rig.failureOf(() => rig.engine.startSession(_config));
      expect(error.failure.code, VoiceFailureCode.invalidState);
    });

    test('endSession tears everything down and is idempotent', () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.listen();
      await rig.engine.endSession();
      await rig.engine.endSession();

      expect(rig.engine.sessionState, isA<VoiceSessionIdle>());
      expect(rig.rec.listening, isFalse);
      expect(rig.synth.active, isFalse);
      expect(rig.audio.active, isFalse);
      expect(rig.audio.hasListeners, isFalse);
    });

    test('operations outside an active session are refused', () async {
      final _Rig rig = _Rig();
      for (final Future<void> Function() op in <Future<void> Function()>[
        rig.engine.startListening,
        () => rig.engine.speak('hi'),
      ]) {
        final VoiceException error = await rig.failureOf(op);
        expect(error.failure.code, VoiceFailureCode.invalidState);
      }
    });
  });

  group('listening', () {
    test('partial then final results become events, and the recognizer is released',
        () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.listen();
      rig.rec.partial('مرح');
      rig.rec.finalResult('مرحبا');
      await rig.pump();

      expect(rig.events.whereType<RecognitionPartial>().single.text, 'مرح');
      expect(rig.events.whereType<RecognitionFinal>().single.text, 'مرحبا');
      expect(rig.rec.listening, isFalse);
    });

    test('a second final, or a blank one, is ignored', () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.listen();
      rig.rec.finalResult('   ');
      rig.rec.finalResult('hello');
      rig.rec.finalResult('again');
      await rig.pump();
      expect(rig.events.whereType<RecognitionFinal>().map((RecognitionFinal e) => e.text), <String>['hello']);
    });

    test('results from a cancelled listen are dropped', () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.listen();
      await rig.engine.cancelListening();
      rig.rec.finalResult('late', callback: 0);
      await rig.pump();
      expect(rig.events.whereType<RecognitionFinal>(), isEmpty);
      expect(
        rig.events.whereType<RecognitionStopped>().single.reason,
        RecognitionStopReason.requested,
      );
    });

    test('a stale result from the previous listen never reaches the new one',
        () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.listen();
      rig.rec.finalResult('first');
      await rig.pump();
      await rig.listen();
      rig.rec.finalResult('stale', callback: 0);
      await rig.pump();
      expect(rig.events.whereType<RecognitionFinal>().map((RecognitionFinal e) => e.text), <String>['first']);
    });

    test('an end-of-listen status before this listen began is ignored', () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.engine.startListening();
      rig.rec.status('done');
      await rig.pump();
      expect(rig.events.whereType<RecognitionStopped>(), isEmpty);

      rig.rec.status('listening');
      rig.rec.partial('still here');
      rig.rec.status('done');
      await rig.pump();
      expect(rig.events.whereType<RecognitionFinal>().single.text, 'still here');
    });

    test('ending with nothing heard is noSpeech, or timeout after the full duration',
        () async {
      final _Rig quick = _Rig();
      await quick.start();
      await quick.listen();
      quick.clock.advance(const Duration(seconds: 3));
      quick.rec.status('done');
      await quick.pump();
      expect(quick.events.whereType<RecognitionStopped>().single.reason, RecognitionStopReason.noSpeech);

      final _Rig long = _Rig();
      await long.start();
      await long.listen();
      long.clock.advance(const Duration(seconds: 59));
      long.rec.status('done');
      await long.pump();
      expect(long.events.whereType<RecognitionStopped>().single.reason, RecognitionStopReason.timeout);
    });

    test('stopListening ends with Stopped(requested) when nothing was heard',
        () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.listen();
      await rig.engine.stopListening();
      rig.rec.status('done');
      await rig.pump();
      expect(rig.events.whereType<RecognitionStopped>().single.reason, RecognitionStopReason.requested);
    });

    test('recognizer errors map to events and failures', () async {
      Future<_Rig> listening() async {
        final _Rig rig = _Rig();
        await rig.start();
        await rig.listen();
        return rig;
      }

      _Rig rig = await listening();
      rig.rec.error('error_no_match');
      await rig.pump();
      expect(rig.events.whereType<RecognitionStopped>().single.reason, RecognitionStopReason.noSpeech);

      const Map<String, VoiceFailureCode> failures = <String, VoiceFailureCode>{
        'error_insufficient_permissions': VoiceFailureCode.permissionDenied,
        'error_recognizer_busy': VoiceFailureCode.recognizerUnavailable,
        'error_language_not_supported': VoiceFailureCode.languageUnavailable,
        'error_network': VoiceFailureCode.recognitionFailed,
      };
      for (final MapEntry<String, VoiceFailureCode> f in failures.entries) {
        rig = await listening();
        rig.rec.error(f.key);
        await rig.pump();
        expect(rig.events.whereType<EngineFailure>().single.failure.code, f.value, reason: f.key);
        expect(rig.rec.listening, isFalse);
      }
    });

    test('an error after partial speech keeps what was heard', () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.listen();
      rig.rec.partial('almost');
      rig.rec.error('error_speech_timeout');
      await rig.pump();
      expect(rig.events.whereType<RecognitionFinal>().single.text, 'almost');
    });

    test('starting twice is a no-op, and a failing platform start throws', () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.listen();
      await rig.engine.startListening();
      expect(rig.rec.listenCalls, 1);

      final _Rig broken = _Rig();
      await broken.start();
      broken.rec.listenError = StateError('platform');
      final VoiceException error = await broken.failureOf(broken.engine.startListening);
      expect(error.failure.code, VoiceFailureCode.recognitionFailed);
    });

    test('a recognizer still live after a final result is cancelled before listening again',
        () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.listen();
      rig.rec.finalResult('one');
      await rig.pump();
      rig.rec.listening = true;
      final int cancels = rig.rec.cancelCalls;
      await rig.engine.startListening();
      expect(rig.rec.cancelCalls, greaterThan(cancels));
    });

    test('sound levels are normalized and throttled', () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.listen();
      for (var i = 0; i < 20; i++) {
        rig.rec.level(i.isEven ? -2 : 9);
        rig.clock.advance(const Duration(milliseconds: 10));
      }
      await rig.pump();
      expect(rig.levels, isNotEmpty);
      expect(rig.levels.length, lessThan(20));
      expect(rig.levels.every((double v) => v >= 0 && v <= 1), isTrue);
    });
  });

  group('playback', () {
    test('chunks play in order; Started once, then Finished', () async {
      final _Rig rig = _Rig(maxChunk: 20);
      await rig.start();
      await rig.speak('First sentence. Second sentence.');
      expect(rig.synth.spoken, <String>['First sentence.']);
      rig.synth.complete();
      rig.synth.start();
      rig.synth.complete();
      await rig.pump();

      expect(rig.synth.spoken, <String>['First sentence.', 'Second sentence.']);
      expect(rig.playbackEvents, <VoiceEngineEvent>[
        const PlaybackStarted(),
        const PlaybackFinished(),
      ]);
    });

    test('a completion before the chunk started is ignored', () async {
      final _Rig rig = _Rig(maxChunk: 20);
      await rig.start();
      await rig.engine.speak('First sentence. Second sentence.');
      rig.synth.spuriousComplete();
      await rig.pump();
      expect(rig.synth.spoken, <String>['First sentence.']);
      expect(rig.playbackEvents, isEmpty);
    });

    test('blank text does nothing', () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.engine.speak('   ');
      expect(rig.synth.spoken, isEmpty);
      expect(rig.playbackEvents, isEmpty);
    });

    test('stopSpeaking cancels, clears the queue, and ignores late callbacks',
        () async {
      final _Rig rig = _Rig(maxChunk: 20);
      await rig.start();
      await rig.speak('First sentence. Second sentence.');
      await rig.engine.stopSpeaking();
      rig.synth.spuriousComplete();
      rig.synth.spuriousCancel();
      await rig.pump();

      expect(rig.synth.spoken, <String>['First sentence.']);
      expect(rig.synth.active, isFalse);
      expect(rig.playbackEvents, <VoiceEngineEvent>[
        const PlaybackStarted(),
        const PlaybackCancelled(),
      ]);
      await rig.engine.stopSpeaking();
      expect(rig.playbackEvents, hasLength(2));
    });

    test('stopping before playback began still ends the run', () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.engine.speak('hello');
      await rig.engine.stopSpeaking();
      expect(rig.playbackEvents, <VoiceEngineEvent>[const PlaybackCancelled()]);
    });

    test('a stale cancel from our own stop does not kill the next utterance',
        () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.speak('one');
      await rig.engine.stopSpeaking();
      await rig.engine.speak('two');
      rig.synth.spuriousCancel();
      await rig.pump();
      expect(rig.synth.active, isTrue);
      rig.synth.start();
      rig.synth.complete();
      await rig.pump();
      expect(rig.playbackEvents.last, const PlaybackFinished());
    });

    test('an OS cancel of playing audio ends the run instead of hanging',
        () async {
      final _Rig rig = _Rig(maxChunk: 20);
      await rig.start();
      await rig.speak('First sentence. Second sentence.');
      rig.synth.osCancel();
      await rig.pump();
      expect(rig.playbackEvents.last, const PlaybackCancelled());
      expect(rig.synth.spoken, <String>['First sentence.']);
    });

    test('a synthesizer that never starts fails instead of hanging', () async {
      final _Rig rig = _Rig(startTimeout: const Duration(milliseconds: 40));
      await rig.start();
      await rig.engine.speak('hello');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(rig.events.whereType<EngineFailure>().single.failure.code, VoiceFailureCode.playbackFailed);
      expect(rig.playbackEvents, <VoiceEngineEvent>[const PlaybackCancelled()]);
    });

    test('a synthesizer error mid-speech fails and ends the run', () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.speak('hello');
      rig.synth.error('engine died');
      await rig.pump();
      expect(rig.events.whereType<EngineFailure>().single.failure.code, VoiceFailureCode.playbackFailed);
      expect(rig.playbackEvents.last, const PlaybackCancelled());
    });

    test('a synthesizer that refuses the request fails', () async {
      final _Rig rig = _Rig();
      await rig.start();
      rig.synth.speakError = StateError('no engine');
      await rig.engine.speak('hello');
      await rig.pump();
      expect(rig.events.whereType<EngineFailure>(), hasLength(1));
      expect(rig.playbackEvents, <VoiceEngineEvent>[const PlaybackCancelled()]);
    });
  });

  group('half-duplex', () {
    test('speaking cancels listening first', () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.listen();
      await rig.engine.speak('hello');
      expect(rig.rec.listening, isFalse);
      expect(rig.synth.active, isTrue);
      expect(
        rig.events.whereType<RecognitionStopped>().single.reason,
        RecognitionStopReason.requested,
      );
    });

    test('listening is refused while speaking', () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.speak('hello');
      final VoiceException error = await rig.failureOf(rig.engine.startListening);
      expect(error.failure.code, VoiceFailureCode.invalidState);
      expect(rig.rec.listening, isFalse);
    });

    test('a recognizer still live after a final result is cancelled before speaking',
        () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.listen();
      rig.rec.finalResult('question');
      await rig.pump();
      rig.rec.listening = true;
      await rig.engine.speak('answer');
      expect(rig.rec.listening, isFalse);
    });
  });

  group('interruptions', () {
    test('a pause-style interruption stops listening and speaking and reports it',
        () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.speak('hello');
      rig.audio.interruption(began: true);
      await rig.pump();

      expect(rig.synth.active, isFalse);
      expect(rig.playbackEvents.last, const PlaybackCancelled());
      expect(rig.events.whereType<AudioInterruption>().single.began, isTrue);
    });

    test('the end of an interruption re-asserts the audio session', () async {
      final _Rig rig = _Rig();
      await rig.start();
      final int before = rig.audio.setActiveTrueCalls;
      rig.audio.interruption(began: false);
      await rig.pump();
      expect(rig.events.whereType<AudioInterruption>().single.began, isFalse);
      expect(rig.audio.setActiveTrueCalls, greaterThan(before));
      expect(rig.audio.configureCalls, 2);
    });

    test('headphones unplugged stops speech', () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.speak('hello');
      rig.audio.noisy();
      await rig.pump();
      expect(rig.synth.active, isFalse);
      expect(rig.playbackEvents.last, const PlaybackCancelled());
    });

    test('interruptions outside an active session are ignored', () async {
      final _Rig rig = _Rig();
      rig.audio.interruption(began: true);
      await rig.pump();
      expect(rig.events, isEmpty);
    });
  });

  group('language and permissions', () {
    test('checkLanguage reports both capabilities', () async {
      final _Rig rig = _Rig();
      final VoiceLanguageSupport support = await rig.engine.checkLanguage(
        recognitionLocaleId: 'ar_SA',
        synthesisLocaleTag: 'ar',
      );
      expect(support, const VoiceLanguageSupport(recognition: true, synthesis: true));
    });

    test('checkLanguage does not touch the recognizer without permission',
        () async {
      final _Rig rig = _Rig();
      rig.perms.status = VoicePermissionStatus.denied;
      final VoiceLanguageSupport support = await rig.engine.checkLanguage(
        recognitionLocaleId: 'ar_SA',
        synthesisLocaleTag: 'ar',
      );
      expect(support.recognition, isFalse);
      expect(support.synthesis, isTrue);
      expect(rig.rec.resolveCalls, 0);
    });

    test('permission calls pass through', () async {
      final _Rig rig = _Rig();
      rig.perms.status = VoicePermissionStatus.denied;
      expect(await rig.engine.checkPermissions(), VoicePermissionStatus.denied);
      expect(await rig.engine.requestPermissions(), VoicePermissionStatus.granted);
    });
  });

  group('dispose', () {
    test('releases everything, closes the streams, and emits nothing after', () async {
      final _Rig rig = _Rig();
      await rig.start();
      await rig.speak('hello');
      final Completer<void> closed = Completer<void>();
      rig.engine.events.listen((_) {}, onDone: closed.complete);

      await rig.engine.dispose();
      await rig.engine.dispose();
      await closed.future.timeout(const Duration(seconds: 2));

      final int count = rig.events.length;
      rig.audio.interruption(began: true);
      rig.synth.start();
      await rig.pump();
      expect(rig.events.length, count);
      expect(rig.synth.active, isFalse);
      expect(rig.audio.active, isFalse);
    });
  });

  test('randomized operations and callbacks keep every invariant', () async {
    final Random random = Random(2026);
    for (var trial = 0; trial < 150; trial++) {
      final _Rig rig = _Rig(startTimeout: const Duration(minutes: 1));
      final List<String> problems = <String>[];
      var runOpen = false;
      var runStarted = false;
      var disposedAt = -1;
      var chunkId = 0;

      rig.engine.events.listen((VoiceEngineEvent e) {
        if (e is PlaybackStarted) {
          if (!runOpen || runStarted) problems.add('Started while open=$runOpen started=$runStarted');
          runStarted = true;
        } else if (e is PlaybackFinished || e is PlaybackCancelled) {
          if (!runOpen) problems.add('terminal event with no open run');
          runOpen = false;
          runStarted = false;
        }
      });

      if (random.nextDouble() < 0.9) {
        await rig.engine.startSession(_config);
        await rig.pump();
      }

      for (var step = 0; step < 40; step++) {
        final double a = random.nextDouble();
        try {
          if (a < 0.05) {
            rig.perms.status = <VoicePermissionStatus>[
              VoicePermissionStatus.granted,
              VoicePermissionStatus.granted,
              VoicePermissionStatus.denied,
            ][random.nextInt(3)];
            await rig.engine.startSession(_config);
          } else if (a < 0.09) {
            await rig.engine.endSession();
          } else if (a < 0.17) {
            await rig.engine.startListening();
          } else if (a < 0.21) {
            await rig.engine.stopListening();
          } else if (a < 0.25) {
            await rig.engine.cancelListening();
          } else if (a < 0.35) {
            final bool blank = random.nextInt(5) == 0;
            final String text = blank ? '  ' : 'c${++chunkId}';
            final bool wasActive = rig.engine.sessionState is VoiceSessionActive;
            await rig.engine.speak(text);
            if (!blank && wasActive) runOpen = true;
          } else if (a < 0.40) {
            await rig.engine.stopSpeaking();
          } else if (a < 0.46) {
            if (rig.rec.resultCallbacks.isNotEmpty) {
              rig.rec.partial('p', callback: random.nextBool() ? -1 : 0);
            }
          } else if (a < 0.52) {
            if (rig.rec.resultCallbacks.isNotEmpty) {
              rig.rec.finalResult(random.nextBool() ? 'text' : ' ', callback: random.nextBool() ? -1 : 0);
            }
          } else if (a < 0.58) {
            rig.rec.status(<String>['listening', 'done', 'notListening'][random.nextInt(3)]);
          } else if (a < 0.61) {
            rig.rec.error(<String>['error_no_match', 'error_network', 'error_recognizer_busy'][random.nextInt(3)]);
          } else if (a < 0.68) {
            rig.synth.start();
          } else if (a < 0.76) {
            if (rig.synth.active) rig.synth.complete();
          } else if (a < 0.80) {
            rig.synth.osCancel();
          } else if (a < 0.83) {
            rig.synth.error('x');
          } else if (a < 0.90) {
            rig.audio.interruption(began: random.nextDouble() < 0.6);
          } else if (a < 0.94) {
            rig.audio.noisy();
          } else if (a < 0.955 && disposedAt < 0) {
            await rig.engine.dispose();
            await rig.pump();
            disposedAt = rig.events.length;
          }
        } on VoiceException {
          // Refusals and setup failures are expected outcomes here.
        }
        await rig.pump();

        if (rig.rec.listening && rig.synth.active) {
          problems.add('half-duplex violated at step $step');
        }
        final VoiceSessionState state = rig.engine.sessionState;
        if (state is VoiceSessionIdle || state is VoiceSessionFailed) {
          if (rig.rec.listening || rig.synth.active || rig.audio.active) {
            problems.add('audio running outside an active session at step $step');
          }
        }
        if (disposedAt >= 0 && rig.events.length != disposedAt) {
          problems.add('events emitted after dispose');
        }
        if (problems.isNotEmpty) break;
      }

      expect(problems, isEmpty, reason: 'trial $trial');

      final List<int> ids = rig.synth.spoken
          .map((String s) => int.parse(s.substring(1)))
          .toList();
      expect(ids.toSet().length, ids.length, reason: 'a chunk was spoken twice');
      expect(ids, <int>[...ids]..sort(), reason: 'chunks spoken out of order');
    }
  });
}
