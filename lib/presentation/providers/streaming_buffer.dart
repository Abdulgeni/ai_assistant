import 'dart:async';

import 'package:ai_assistant/domain/entities/value_object.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable snapshot of the in-flight assistant text, published to the UI.
final class StreamingBufferState extends ValueObject {
  const StreamingBufferState({this.messageId, this.text = ''});

  const StreamingBufferState.idle()
      : messageId = null,
        text = '';

  /// Id of the message currently being streamed, or null when idle.
  final String? messageId;
  final String text;

  bool get isActive => messageId != null;

  @override
  List<Object?> get props => <Object?>[messageId, text];

  @override
  String toString() =>
      'StreamingBufferState(messageId: $messageId, chars: ${text.length})';
}

/// How often the buffer may publish a new snapshot while tokens stream in.
/// Keep within 30 to 60 ms; tests override this.
final streamingFlushIntervalProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 40),
);

/// Holds the text of the single in-flight assistant message so that only the
/// active bubble rebuilds per token. The immutable message list is updated
/// ONCE, when the stream ends, using the text returned by [finish].
///
/// Publishing is throttled: the first token after idle publishes immediately
/// (low latency), later tokens are coalesced to at most one publish per
/// flush interval, and a trailing publish flushes the remainder.
///
/// Every call carries the message id so tokens from a stream that was
/// cancelled or replaced can never leak into the new message.
class StreamingBuffer extends Notifier<StreamingBufferState> {
  final StringBuffer _text = StringBuffer();
  Timer? _cooldown;
  bool _dirty = false;

  @override
  StreamingBufferState build() {
    ref.onDispose(_stopTimer);
    return const StreamingBufferState.idle();
  }

  /// Starts buffering for [messageId], discarding any previous buffer. Callers
  /// cancel the previous stream subscription first.
  void begin(String messageId) {
    _stopTimer();
    _text.clear();
    _dirty = false;
    state = StreamingBufferState(messageId: messageId);
  }

  /// Appends a token. Ignored unless [messageId] is the active message.
  void append(String messageId, String token) {
    if (state.messageId != messageId || token.isEmpty) return;
    _text.write(token);
    if (_cooldown == null) {
      _publish(messageId);
      _cooldown = Timer(ref.read(streamingFlushIntervalProvider), () {
        _onCooldownEnd(messageId);
      });
    } else {
      _dirty = true;
    }
  }

  /// Ends buffering for [messageId] and returns the complete text so the caller
  /// can commit it to the message list in the same synchronous block. Returns
  /// an empty string, and changes nothing, if [messageId] is not active.
  String finish(String messageId) {
    if (state.messageId != messageId) return '';
    _stopTimer();
    final String text = _text.toString();
    _text.clear();
    _dirty = false;
    state = const StreamingBufferState.idle();
    return text;
  }

  /// Drops the buffered text for [messageId] without returning it.
  void discard(String messageId) {
    finish(messageId);
  }

  void _onCooldownEnd(String messageId) {
    _cooldown = null;
    if (_dirty && state.messageId == messageId) {
      _publish(messageId);
      _cooldown = Timer(ref.read(streamingFlushIntervalProvider), () {
        _onCooldownEnd(messageId);
      });
    }
  }

  void _publish(String messageId) {
    _dirty = false;
    state = StreamingBufferState(messageId: messageId, text: _text.toString());
  }

  void _stopTimer() {
    _cooldown?.cancel();
    _cooldown = null;
  }
}

final streamingBufferProvider =
    NotifierProvider<StreamingBuffer, StreamingBufferState>(
  StreamingBuffer.new,
);

/// The live text for one message, or null when that message is not the one
/// currently streaming. Watching this rebuilds a bubble only when its own text
/// changes.
final streamingTextProvider = Provider.autoDispose.family<String?, String>(
  (ref, messageId) => ref.watch(
    streamingBufferProvider.select(
      (state) => state.messageId == messageId ? state.text : null,
    ),
  ),
);
