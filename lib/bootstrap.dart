import 'package:ai_assistant/core/network/sse_client.dart';
import 'package:ai_assistant/data/local/app_database.dart';
import 'package:ai_assistant/data/repositories/ai_repository_impl.dart';
import 'package:ai_assistant/data/repositories/chat_repository_impl.dart';
import 'package:ai_assistant/presentation/providers/core_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final AppDatabase database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final dioProvider = Provider<Dio>((ref) {
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: ref.watch(appConfigProvider).gatewayBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 30),
      // receiveTimeout is intentionally unset: SseClient owns stream timeouts.
    ),
  );
  ref.onDispose(dio.close);
  return dio;
});

final sseClientProvider = Provider<SseClient>(
  (ref) => SseClient(ref.watch(dioProvider)),
);

/// DEVELOPMENT stand-in: returns the `DEV_AUTH_TOKEN` build constant. Replace
/// with a provider that fetches and refreshes a real user token (honoring
/// `forceRefresh`, and de-duplicating concurrent refreshes).
final authTokenProviderProvider = Provider<AuthTokenProvider>((ref) {
  final String token = ref.watch(appConfigProvider).devAuthToken;
  return ({required bool forceRefresh}) async => token.isEmpty ? null : token;
});

/// The real implementations of the dependencies `core_providers.dart` leaves
/// abstract. Tests pass fakes instead of calling this.
List<Override> productionOverrides() => <Override>[
      chatRepositoryProvider.overrideWith(
        (ref) => ChatRepositoryImpl(ref.watch(appDatabaseProvider)),
      ),
      llmClientProvider.overrideWith(
        (ref) => GatewayLlmClient(
          sseClient: ref.watch(sseClientProvider),
          authTokenProvider: ref.watch(authTokenProviderProvider),
        ),
      ),
    ];
