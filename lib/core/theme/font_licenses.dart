import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const String _oflAsset = 'assets/fonts/OFL.txt';

/// Adds the IBM Plex Sans Arabic license (SIL OFL 1.1) to Flutter's license
/// registry so it appears on the in-app licenses page. The OFL requires the
/// license text to travel with the font. Call once before `runApp`.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    final String text = await rootBundle.loadString(_oflAsset);
    yield LicenseEntryWithLineBreaks(<String>['IBM Plex Sans Arabic'], text);
  });
}
