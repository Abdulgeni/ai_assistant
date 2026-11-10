import 'package:flutter/foundation.dart';

/// Build-time configuration, supplied with `--dart-define`:
///
///   flutter run \
///     --dart-define=GATEWAY_BASE_URL=https://gateway.example.com \
///     --dart-define=DEV_AUTH_TOKEN=`<token>`    (development only)
final class AppConfig {
  const AppConfig({required this.gatewayBaseUrl, required this.devAuthToken});

  factory AppConfig.fromEnvironment() => const AppConfig(
        gatewayBaseUrl: String.fromEnvironment('GATEWAY_BASE_URL'),
        devAuthToken: String.fromEnvironment('DEV_AUTH_TOKEN'),
      );

  final String gatewayBaseUrl;

  /// DEVELOPMENT ONLY. A token baked into a build is extractable from the app;
  /// production authentication must obtain short-lived tokens at runtime.
  final String devAuthToken;

  /// True when the gateway address is usable. Release builds require https.
  bool get isConfigured {
    final Uri? uri = Uri.tryParse(gatewayBaseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    if (kReleaseMode) return uri.scheme == 'https';
    return uri.scheme == 'https' || uri.scheme == 'http';
  }
}
