import 'package:ai_assistant/core/localization/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';

export 'package:ai_assistant/core/localization/generated/app_localizations.dart';

/// `context.l10n.send` instead of `AppLocalizations.of(context).send`.
extension AppL10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
