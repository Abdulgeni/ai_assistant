import 'package:ai_assistant/core/config/app_config.dart';
import 'package:ai_assistant/core/platform/platform_actions.dart';
import 'package:ai_assistant/domain/chat_repository.dart';
import 'package:ai_assistant/domain/llm_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Build-time configuration (`--dart-define`). Tests override it.
final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

/// Must be overridden in the root `ProviderScope` (the app bootstrap wires the
/// Drift repository; tests supply fakes).
final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => throw UnimplementedError(
    'chatRepositoryProvider must be overridden in ProviderScope.',
  ),
);

/// Must be overridden in the root `ProviderScope` (the app bootstrap wires the
/// gateway client; tests supply fakes).
final llmClientProvider = Provider<LlmClient>(
  (ref) => throw UnimplementedError(
    'llmClientProvider must be overridden in ProviderScope.',
  ),
);

/// Injectable time and identity, so state logic is deterministic in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final idGeneratorProvider = Provider<String Function()>((ref) {
  const Uuid uuid = Uuid();
  return () => uuid.v4();
});

final chatPageSizeProvider = Provider<int>((ref) => 50);

/// Hard ceiling on one generation. A safety net above the transport
/// watchdogs, for a server that heartbeats forever without producing output.
final chatMaxGenerationTimeProvider = Provider<Duration>(
  (ref) => const Duration(minutes: 5),
);

/// Runs once per app start, BEFORE any history is loaded: messages left in the
/// streaming state by a crash become `failed`. Returns how many were fixed.
final storageRecoveryProvider = FutureProvider<int>(
  (ref) => ref.read(chatRepositoryProvider).recoverInterruptedStreams(),
);

/// Only one assistant reply may stream at a time, app-wide, because the
/// streaming buffer holds a single message. Not reactive on purpose: the UI
/// observes `streamingBufferProvider` to know whether any reply is streaming.
final generationLockProvider = Provider<GenerationLock>(
  (ref) => GenerationLock(),
);

final class GenerationLock {
  String? _holder;

  /// The conversation currently generating, if any.
  String? get holder => _holder;

  /// True if [owner] now holds the lock (it may already have held it).
  bool tryAcquire(String owner) {
    if (_holder == null || _holder == owner) {
      _holder = owner;
      return true;
    }
    return false;
  }

  /// Releases the lock only if [owner] holds it.
  void release(String owner) {
    if (_holder == owner) _holder = null;
  }
}

/// Clipboard, share sheet, and external links. Tests override it with a fake.
final platformActionsProvider = Provider<PlatformActions>(
  (ref) => const DefaultPlatformActions(),
);
