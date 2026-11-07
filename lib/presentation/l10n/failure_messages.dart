import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/domain/entities/stream_event.dart';
import 'package:ai_assistant/domain/entities/voice_state.dart';

/// Localized, user-facing text for a stream failure. The switch is exhaustive,
/// so adding a [StreamFailureCode] without a message fails to compile.
String streamFailureMessage(AppLocalizations l10n, StreamFailureCode code) =>
    switch (code) {
      StreamFailureCode.unauthorized => l10n.errorUnauthorized,
      StreamFailureCode.rateLimited => l10n.errorRateLimited,
      StreamFailureCode.network => l10n.errorNetwork,
      StreamFailureCode.idleTimeout => l10n.errorTimeout,
      StreamFailureCode.server => l10n.errorServer,
      StreamFailureCode.malformedStream => l10n.errorMalformed,
      StreamFailureCode.unknown => l10n.errorUnknown,
    };

/// Localized, user-facing text for a voice failure (exhaustive).
String voiceFailureMessage(AppLocalizations l10n, VoiceFailureCode code) =>
    switch (code) {
      VoiceFailureCode.permissionDenied ||
      VoiceFailureCode.permissionPermanentlyDenied =>
        l10n.micPermissionBody,
      VoiceFailureCode.languageUnavailable => l10n.voiceLanguageUnavailable,
      VoiceFailureCode.recognizerUnavailable ||
      VoiceFailureCode.audioSessionFailed ||
      VoiceFailureCode.unsupportedDuplexMode ||
      VoiceFailureCode.invalidState ||
      VoiceFailureCode.recognitionFailed ||
      VoiceFailureCode.playbackFailed ||
      VoiceFailureCode.unknown =>
        l10n.errorVoiceGeneric,
    };
