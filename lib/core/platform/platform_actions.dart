import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Everything the UI does to the outside world. One interface, so widgets
/// never call a plugin directly and tests inject a fake.
abstract interface class PlatformActions {
  Future<void> copyText(String text);

  /// [origin] anchors the iPad share popover to the tapped widget.
  Future<void> shareText(String text, {Rect? origin});

  /// Opens [uri] in the system browser or another app. Returns false if it
  /// could not be opened. Callers must have confirmed with the user.
  Future<bool> openUrl(Uri uri);
}

final class DefaultPlatformActions implements PlatformActions {
  const DefaultPlatformActions();

  @override
  Future<void> copyText(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  @override
  Future<void> shareText(String text, {Rect? origin}) async {
    await SharePlus.instance.share(
      ShareParams(text: text, sharePositionOrigin: origin),
    );
  }

  @override
  Future<bool> openUrl(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// The URI for [href] if it is safe to offer to open, else null.
///
/// Only absolute `http`/`https` links with a host and no embedded credentials
/// qualify. Links come from model output, which is untrusted: `javascript:`,
/// `intent:`, `file:`, relative links, and `user:pass@host` (a phishing
/// pattern) are all refused.
Uri? parseWebLink(String? href) {
  if (href == null) return null;
  final Uri? uri = Uri.tryParse(href.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  if (uri.userInfo.isNotEmpty) return null;
  final String scheme = uri.scheme.toLowerCase();
  return scheme == 'https' || scheme == 'http' ? uri : null;
}
