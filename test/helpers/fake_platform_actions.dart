import 'dart:ui' show Rect;

import 'package:ai_assistant/core/platform/platform_actions.dart';

class FakePlatformActions implements PlatformActions {
  final List<String> copied = <String>[];
  final List<String> shared = <String>[];
  final List<Uri> opened = <Uri>[];

  @override
  Future<void> copyText(String text) async {
    copied.add(text);
  }

  @override
  Future<void> shareText(String text, {Rect? origin}) async {
    shared.add(text);
  }

  @override
  Future<bool> openUrl(Uri uri) async {
    opened.add(uri);
    return true;
  }
}
