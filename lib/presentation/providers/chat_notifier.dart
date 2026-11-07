import 'dart:async';

import 'package:ai_assistant/domain/chat_repository.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/stream_event.dart';
import 'package:ai_assistant/domain/llm_client.dart';
import 'package:ai_assistant/presentation/providers/app_settings_providers.dart';
import 'package:ai_assistant/presentation/providers/chat_context.dart';
import 'package:ai_assistant/presentation/providers/chat_state.dart';
import 'package:ai_assistant/presentation/providers/core_providers.dart';
import 'package:ai_assistant/presentation/providers/streaming_buffer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State and behavior of one conversation.
///
/// Flow of a turn:
///  1. [send] appends the user message and an empty assistant placeholder,
///     saves both, and starts the stream. The placeholder is saved so a crash
///     leaves a visible `failed` message (see `recoverInterruptedStreams`).
///  2. Tokens go ONLY to the streaming buffer; this notifier's state is not
///     touched per token.
///  3. On done/error the buffer's text is committed into the message list in
///     one synchronous step, and saved once.
///
/// Rules:
///  * One reply streams at a time app-wide ([GenerationLock]).
///  * Persistence goes through a FIFO queue, so a slow early write can never
///    land after, and overwrite, a later one.
///  * Callbacks from a superseded stream are ignored via a generation counter.
///  * Do not invalidate this provider while streaming; call [stop] first.
class ChatNotifier extends FamilyNotifier<ChatState, String> {
  late String _conversationId;
  late GenerationLock _lock;
  StreamSubscription<StreamEvent>? _subscription;
  Timer? _deadline;
  int _generation = 0;
  bool _disposed = false;
  Future<void> _writes = Future<void>.value();

  @override
  ChatState build(String conversationId) {
    _conversationId = conversationId;
    _lock = ref.read(generationLockProvider);
    _disposed = false;
    _generation = 0;
    _writes = Future<void>.value();
    ref.onDispose(_onDispose);
    unawaited(_load());
    return const ChatState();
  }

  // ------------------------------------------------------------ public API

  /// Sends [text]. Returns false (and does nothing) if it is blank, history is
  /// not loaded yet, a reply is already streaming here, or another
  /// conversation is generating.
  bool send(String text) {
    final String content = text.trim();
    if (_disposed ||
        content.isEmpty ||
        state.status != ChatLoadStatus.ready ||
        state.isStreaming) {
      return false;
    }
    if (!_lock.tryAcquire(_conversationId)) return false;

    final ChatMessage user = ChatMessage.user(
      id: ref.read(idGeneratorProvider)(),
      conversationId: _conversationId,
      content: content,
      createdAt: ref.read(clockProvider)(),
    );
    state = state.copyWith(
      messages: <ChatMessage>[...state.messages, user],
      clearFailure: true,
    );
    _persist((ChatRepository repo) => repo.saveMessage(user));
    _startAssistantTurn();
    return true;
  }

  /// Stops the current reply. Whatever text arrived is kept as a `cancelled`
  /// message; if nothing arrived, the placeholder is removed.
  Future<void> stop() async {
    final String? id = state.streamingMessageId;
    if (_disposed || id == null) return;

    // Anything still in flight for this turn is now stale.
    _generation++;
    _deadline?.cancel();
    _deadline = null;
    final StreamSubscription<StreamEvent>? subscription = _subscription;
    _subscription = null;

    final ChatMessage? current = _messageById(id);
    final String text = ref.read(streamingBufferProvider.notifier).finish(id);

    if (current == null) {
      state = state.copyWith(clearStreamingMessageId: true, clearFailure: true);
    } else if (text.trim().isEmpty) {
      state = state.copyWith(
        messages: state.messages
            .where((ChatMessage m) => m.id != id)
            .toList(growable: false),
        clearStreamingMessageId: true,
        clearFailure: true,
      );
      _persist((ChatRepository repo) => repo.deleteMessage(id));
    } else {
      final ChatMessage cancelled =
          current.copyWith(content: text, status: MessageStatus.cancelled);
      _replaceMessage(cancelled);
      state = state.copyWith(clearStreamingMessageId: true, clearFailure: true);
      _persist((ChatRepository repo) => repo.saveMessage(cancelled));
    }
    _lock.release(_conversationId);
    await subscription?.cancel();
  }

  /// Retry / regenerate: drops the last assistant message (if the last message
  /// is one) and streams a fresh answer to the last user message. Returns
  /// false if that is not possible right now.
  bool regenerate() {
    if (_disposed ||
        state.status != ChatLoadStatus.ready ||
        state.isStreaming ||
        state.messages.isEmpty) {
      return false;
    }
    final List<ChatMessage> messages = state.messages;
    final ChatMessage last = messages.last;
    final List<ChatMessage> remaining = last.role == ChatRole.assistant
        ? messages.sublist(0, messages.length - 1)
        : messages;
    if (remaining.isEmpty || remaining.last.role != ChatRole.user) return false;
    if (!_lock.tryAcquire(_conversationId)) return false;

    if (last.role == ChatRole.assistant) {
      state = state.copyWith(messages: remaining);
      _persist((ChatRepository repo) => repo.deleteMessage(last.id));
    }
    state = state.copyWith(clearFailure: true);
    _startAssistantTurn();
    return true;
  }

  /// Clears the failure banner.
  void dismissFailure() {
    if (!_disposed && state.failure != null) {
      state = state.copyWith(clearFailure: true);
    }
  }

  /// Loads the next page of older messages (no-op while loading or at the top).
  Future<void> loadOlder() async {
    if (_disposed ||
        state.status != ChatLoadStatus.ready ||
        !state.hasMoreOlder ||
        state.isLoadingOlder ||
        state.messages.isEmpty) {
      return;
    }
    state = state.copyWith(isLoadingOlder: true);
    try {
      final int pageSize = ref.read(chatPageSizeProvider);
      final List<ChatMessage> page =
          await ref.read(chatRepositoryProvider).loadMessages(
                _conversationId,
                limit: pageSize,
                beforeMessageId: state.messages.first.id,
              );
      if (_disposed) return;
      state = state.copyWith(
        messages: <ChatMessage>[...page, ...state.messages],
        hasMoreOlder: page.length == pageSize,
        isLoadingOlder: false,
      );
    } on Object {
      if (_disposed) return;
      state = state.copyWith(isLoadingOlder: false);
    }
  }

  /// Retries the initial history load after a failure.
  Future<void> reload() async {
    if (_disposed || state.isStreaming) return;
    state = const ChatState();
    await _load();
  }

  /// Completes when every queued write has been attempted. Never throws.
  /// Await it before tearing the app down (and in tests).
  Future<void> flushWrites() => _writes;

  // --------------------------------------------------------------- loading

  Future<void> _load() async {
    try {
      await ref.read(storageRecoveryProvider.future);
      if (_disposed) return;
      final int pageSize = ref.read(chatPageSizeProvider);
      final List<ChatMessage> page = await ref
          .read(chatRepositoryProvider)
          .loadMessages(_conversationId, limit: pageSize);
      if (_disposed) return;
      state = state.copyWith(
        status: ChatLoadStatus.ready,
        messages: page,
        hasMoreOlder: page.length == pageSize,
      );
    } on Object {
      if (_disposed) return;
      state = state.copyWith(status: ChatLoadStatus.loadFailed);
    }
  }

  // ------------------------------------------------------------ generation

  void _startAssistantTurn() {
    final int generation = ++_generation;
    final ChatMessage placeholder = ChatMessage.assistantPlaceholder(
      id: ref.read(idGeneratorProvider)(),
      conversationId: _conversationId,
      createdAt: ref.read(clockProvider)(),
    );
    final List<ChatMessage> history = selectContext(state.messages);

    state = state.copyWith(
      messages: <ChatMessage>[...state.messages, placeholder],
      streamingMessageId: placeholder.id,
    );
    ref.read(streamingBufferProvider.notifier).begin(placeholder.id);
    _persist((ChatRepository repo) => repo.saveMessage(placeholder));

    _deadline = Timer(
      ref.read(chatMaxGenerationTimeProvider),
      () => _onDeadline(generation, placeholder.id),
    );

    final Stream<StreamEvent> stream = ref.read(llmClientProvider).streamChat(
          ChatRequest(
            conversationId: _conversationId,
            messages: history,
            localeTag: ref.read(localeProvider)?.languageCode,
          ),
        );
    _subscription = stream.listen(
      (StreamEvent event) => _onEvent(generation, placeholder.id, event),
      // The LlmClient contract says the stream never errors or closes without a
      // terminal event; both are handled anyway so the UI can never hang.
      onError: (Object error, StackTrace _) => _finalize(
        placeholder.id,
        generation: generation,
        failure: StreamFailure(
          code: StreamFailureCode.unknown,
          message: 'Unexpected stream error (${error.runtimeType}).',
        ),
      ),
      onDone: () => _finalize(
        placeholder.id,
        generation: generation,
        failure: const StreamFailure(
          code: StreamFailureCode.network,
          message: 'The stream closed without a result.',
        ),
      ),
    );
  }

  void _onEvent(int generation, String id, StreamEvent event) {
    if (!_isCurrent(generation, id)) return;
    switch (event) {
      case TokenEvent(:final String text):
        ref.read(streamingBufferProvider.notifier).append(id, text);
      case SourcesEvent(:final List<SourceReference> sources):
        final ChatMessage? current = _messageById(id);
        if (current != null) _replaceMessage(current.copyWith(sources: sources));
      case DoneEvent():
        _finalize(id, generation: generation);
      case ErrorEvent(:final StreamFailure failure):
        _finalize(id, generation: generation, failure: failure);
    }
  }

  void _onDeadline(int generation, String id) {
    _finalize(
      id,
      generation: generation,
      failure: const StreamFailure(
        code: StreamFailureCode.idleTimeout,
        message: 'Generation exceeded the maximum duration.',
      ),
    );
  }

  /// Ends the turn for [id]: commits the buffered text, stores the result
  /// once, and releases the lock. Ignored if the turn was superseded.
  void _finalize(String id, {required int generation, StreamFailure? failure}) {
    if (!_isCurrent(generation, id)) return;

    _deadline?.cancel();
    _deadline = null;
    final StreamSubscription<StreamEvent>? subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());

    final ChatMessage? current = _messageById(id);
    final String text = ref.read(streamingBufferProvider.notifier).finish(id);

    StreamFailure? effectiveFailure = failure;
    var status = failure == null ? MessageStatus.complete : MessageStatus.failed;
    if (failure == null && text.trim().isEmpty) {
      // A "successful" reply with no content is a failure, not an empty bubble.
      status = MessageStatus.failed;
      effectiveFailure = const StreamFailure(
        code: StreamFailureCode.unknown,
        message: 'The model returned no content.',
      );
    }

    if (current != null) {
      final ChatMessage committed =
          current.copyWith(content: text, status: status);
      _replaceMessage(committed);
      _persist((ChatRepository repo) => repo.saveMessage(committed));
    }
    state = state.copyWith(
      clearStreamingMessageId: true,
      failure: effectiveFailure,
      clearFailure: effectiveFailure == null,
    );
    _lock.release(_conversationId);
  }

  // --------------------------------------------------------------- helpers

  bool _isCurrent(int generation, String id) =>
      !_disposed && generation == _generation && state.streamingMessageId == id;

  ChatMessage? _messageById(String id) {
    for (final ChatMessage message in state.messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  void _replaceMessage(ChatMessage message) {
    state = state.copyWith(
      messages: <ChatMessage>[
        for (final ChatMessage m in state.messages)
          if (m.id == message.id) message else m,
      ],
    );
  }

  void _persist(Future<void> Function(ChatRepository repo) write) {
    final ChatRepository repo = ref.read(chatRepositoryProvider);
    _writes = _writes.then((_) => write(repo)).catchError((Object error) {
      if (!_disposed) state = state.copyWith(storageError: true);
    });
  }

  void _onDispose() {
    _disposed = true;
    _deadline?.cancel();
    _deadline = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    // The lock is a plain object, so releasing it here does not touch `ref`.
    _lock.release(_conversationId);
  }
}

final chatNotifierProvider =
    NotifierProvider.family<ChatNotifier, ChatState, String>(
  ChatNotifier.new,
);
