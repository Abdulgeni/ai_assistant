import 'package:ai_assistant/app.dart';
import 'package:ai_assistant/bootstrap.dart';
import 'package:ai_assistant/core/theme/font_licenses.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  runApp(
    ProviderScope(
      overrides: productionOverrides(),
      child: const AppRoot(),
    ),
  );
}
