import 'dart:convert';

import 'package:ai_assistant/core/network/sse_parser.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/stream_event.dart';
import 'package:ai_assistant/domain/llm_client.dart';

/// Wire contract v1 between the app and the edge gateway.
///
/// REQUEST   `POST /v1/chat/stream`, JSON body:
///   `{"conversationId": "...", "locale": "ar",
///     "messages": [{"role": "user|assistant|system", "content": "..."}]}`
///   (`locale` is omitted when unknown.) Auth: `Authorization: Bearer <jwt>`.
///
/// RESPONSE  `200 text/event-stream`. Every event ends with a blank line.
///   `event: token`    `data: {"text": "..."}`            (text never empty)
///   `event: sources`  `data: {"sources": [{"id","title","uri"?,"snippet"?}]}`
///   `event: error`    `data: {"code","message"?,"retryAfterMs"?}`   terminal
///   `event: done`     `data: {"finishReason"?: "stop|length|content_filter"}`
///                                                                  terminal
///   Also accepted: an unnamed event whose data is `[DONE]` (terminal).
///   Unknown event names (e.g. `ping`, `usage`) are ignored.
///   Comment lines (`: keep-alive`) are heartbeats and must be sent at least
///   every ~10 s.
///
/// Non-2xx responses carry no meaning beyond the status code and a possible
/// `Retry-After` header; the body is never interpreted.
abstract final class WireEvents {
  static const String token = 'token';
  static const String sources = 'sources';
  static const String error = 'error';
  static const String done = 'done';

  /// OpenAI-style end marker, accepted as the data of an unnamed event.
  static const String legacyDoneSentinel = '[DONE]';
}

abstract final class WireErrorCodes {
  static const String unauthorized = 'unauthorized';
  static const String rateLimited = 'rate_limited';
  static const String serverError = 'server_error';
  static const String timeout = 'timeout';
  static const String upstreamTimeout = 'upstream_timeout';
}

const int _maxMessageLength = 200;

/// Request body for [ChatRequest]. Only role and content leave the device.
///
/// The request must not contain the in-flight assistant placeholder (see
/// [LlmClient]); this is asserted in debug builds, and the gateway must also
/// reject empty messages.
Map<String, Object?> encodeChatRequest(ChatRequest request) {
  assert(
    request.messages.every((ChatMessage m) => m.status != MessageStatus.streaming),
    'ChatRequest must not include a streaming placeholder message.',
  );
  return <String, Object?>{
    'conversationId': request.conversationId,
    if (request.localeTag != null) 'locale': request.localeTag,
    'messages': <Map<String, String>>[
      for (final ChatMessage message in request.messages)
        <String, String>{'role': message.role.name, 'content': message.content},
    ],
  };
}

/// Maps one SSE message to a domain event, or null when it carries nothing the
/// app should act on (unknown event, empty token, empty sources, unnamed event
/// that is not the done sentinel).
///
/// A known event with an unusable payload becomes a terminal
/// `malformedStream` [ErrorEvent] instead of being silently skipped.
StreamEvent? decodeStreamEvent(SseMessage message) {
  if (message.event == SseMessage.defaultEvent) {
    return message.data.trim() == WireEvents.legacyDoneSentinel
        ? const DoneEvent()
        : null;
  }
  switch (message.event) {
    case WireEvents.token:
      return _decodeToken(message.data);
    case WireEvents.sources:
      return _decodeSources(message.data);
    case WireEvents.error:
      return _decodeError(message.data);
    case WireEvents.done:
      return _decodeDone(message.data);
    default:
      return null;
  }
}

StreamEvent? _decodeToken(String data) {
  final Object? text = _decodeObject(data)?['text'];
  if (text is! String) return _malformed(WireEvents.token);
  if (text.isEmpty) return null;
  return TokenEvent(text);
}

StreamEvent? _decodeSources(String data) {
  final Object? raw = _decodeObject(data)?['sources'];
  if (raw is! List<Object?>) return _malformed(WireEvents.sources);

  final List<SourceReference> sources = <SourceReference>[];
  for (var i = 0; i < raw.length; i++) {
    final Object? entry = raw[i];
    if (entry is! Map<String, Object?>) continue;
    final Object? title = entry['title'];
    if (title is! String || title.isEmpty) continue;
    final Object? id = entry['id'];
    sources.add(
      SourceReference(
        id: id is String && id.isNotEmpty ? id : 'source-$i',
        title: title,
        uri: _optionalString(entry['uri']),
        snippet: _optionalString(entry['snippet']),
      ),
    );
  }
  return sources.isEmpty ? null : SourcesEvent(sources);
}

StreamEvent _decodeError(String data) {
  final Map<String, Object?>? json = _decodeObject(data);
  final Object? code = json?['code'];
  final Object? message = json?['message'];
  final Object? retryAfterMs = json?['retryAfterMs'];
  return ErrorEvent(
    StreamFailure(
      code: _failureCodeFor(code is String ? code : null),
      message: message is String && message.isNotEmpty
          ? _truncate(message)
          : 'The server reported an error.',
      retryAfter: retryAfterMs is int && retryAfterMs >= 0
          ? Duration(milliseconds: retryAfterMs)
          : null,
    ),
  );
}

/// Lenient on purpose: a terminal event must never fail because its optional
/// payload is empty or malformed.
StreamEvent _decodeDone(String data) =>
    DoneEvent(finishReason: _finishReasonFor(_decodeObject(data)?['finishReason']));

StreamFailureCode _failureCodeFor(String? wire) => switch (wire) {
      WireErrorCodes.unauthorized => StreamFailureCode.unauthorized,
      WireErrorCodes.rateLimited => StreamFailureCode.rateLimited,
      WireErrorCodes.serverError => StreamFailureCode.server,
      WireErrorCodes.timeout ||
      WireErrorCodes.upstreamTimeout =>
        StreamFailureCode.idleTimeout,
      _ => StreamFailureCode.unknown,
    };

FinishReason _finishReasonFor(Object? wire) => switch (wire) {
      null || 'stop' => FinishReason.stop,
      'length' => FinishReason.length,
      'content_filter' => FinishReason.contentFilter,
      _ => FinishReason.other,
    };

ErrorEvent _malformed(String event) => ErrorEvent(
      StreamFailure(
        code: StreamFailureCode.malformedStream,
        message: 'Invalid "$event" event payload.',
      ),
    );

Map<String, Object?>? _decodeObject(String data) {
  try {
    final Object? decoded = jsonDecode(data);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

String? _optionalString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

String _truncate(String text) => text.length <= _maxMessageLength
    ? text
    : text.substring(0, _maxMessageLength);
