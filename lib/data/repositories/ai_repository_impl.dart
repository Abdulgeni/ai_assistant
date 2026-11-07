import 'dart:async';

import 'package:ai_assistant/core/network/sse_client.dart';
import 'package:ai_assistant/core/network/sse_exceptions.dart';
import 'package:ai_assistant/core/network/sse_parser.dart';
import 'package:ai_assistant/data/models/stream_failure_mapper.dart';
import 'package:ai_assistant/data/models/wire_contract.dart';
import 'package:ai_assistant/domain/entities/stream_event.dart';
import 'package:ai_assistant/domain/llm_client.dart';

/// Supplies the gateway JWT. With [forceRefresh] true it must bypass any cache
/// and obtain a fresh token (used once after a 401). Returning null sends the
/// request unauthenticated (the gateway will answer 401).
typedef AuthTokenProvider = Future<String?> Function({
  required bool forceRefresh,
});

/// [LlmClient] backed by the edge gateway over SSE.
///
/// Honors the full stream contract documented on [LlmClient]. The guarantee of
/// exactly one terminal event holds because [SseClient] always ends its stream
/// (its watchdogs turn a silent connection into an error); this class relies
/// on that and does not add its own timers.
///
/// Only a 401 is retried automatically (once, with a refreshed token), because
/// it is rejected before any model work. Every other failure is surfaced and
/// left to the user's Retry, since re-running a model call costs money.
final class GatewayLlmClient implements LlmClient {
  GatewayLlmClient({
    required SseClient sseClient,
    required AuthTokenProvider authTokenProvider,
    this.path = defaultPath,
  })  : _sse = sseClient,
        _authTokenProvider = authTokenProvider;

  static const String defaultPath = '/v1/chat/stream';

  final SseClient _sse;
  final AuthTokenProvider _authTokenProvider;
  final String path;

  @override
  Stream<StreamEvent> streamChat(ChatRequest request) {
    assert(
      request.messages.isNotEmpty,
      'ChatRequest.messages must not be empty.',
    );

    late final StreamController<StreamEvent> controller;
    StreamSubscription<SseMessage>? subscription;

    // True once a terminal event was emitted or the consumer cancelled; from
    // then on nothing more is ever added to [controller].
    var closed = false;
    var refreshed = false;

    void emit(StreamEvent event) {
      if (closed) return;
      controller.add(event);
      if (event is DoneEvent || event is ErrorEvent) {
        closed = true;
        // Aborts the underlying request (SseClient cancels on unsubscribe).
        unawaited(subscription?.cancel());
        unawaited(controller.close());
      }
    }

    Future<void> attempt({required bool forceRefresh}) async {
      String? token;
      try {
        token = await _authTokenProvider(forceRefresh: forceRefresh);
      } on Object {
        emit(
          const ErrorEvent(
            StreamFailure(
              code: StreamFailureCode.unauthorized,
              message: 'Could not obtain an auth token.',
            ),
          ),
        );
        return;
      }
      // The consumer may have cancelled while the token was being fetched.
      if (closed) return;

      subscription = _sse
          .post(
            path,
            data: encodeChatRequest(request),
            headers: <String, Object?>{
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .listen(
        (SseMessage message) {
          final StreamEvent? event = decodeStreamEvent(message);
          if (event != null) emit(event);
        },
        onError: (Object error, StackTrace _) {
          if (error is SseHttpException &&
              error.statusCode == 401 &&
              !refreshed) {
            refreshed = true;
            unawaited(attempt(forceRefresh: true));
            return;
          }
          emit(
            ErrorEvent(
              error is SseException
                  ? mapSseException(error)
                  : StreamFailure(
                      code: StreamFailureCode.unknown,
                      message: 'Unexpected error (${error.runtimeType}).',
                    ),
            ),
          );
        },
        onDone: () {
          // The source ended without a terminal event: the connection was cut.
          emit(
            const ErrorEvent(
              StreamFailure(
                code: StreamFailureCode.network,
                message: 'The stream ended before completion.',
              ),
            ),
          );
        },
        cancelOnError: true,
      );
    }

    controller = StreamController<StreamEvent>(
      onListen: () => unawaited(attempt(forceRefresh: false)),
      onCancel: () async {
        closed = true;
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }
}
