import 'package:ai_assistant/core/platform/platform_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseWebLink accepts', () {
    test('https and http links with a host', () {
      expect(parseWebLink('https://example.com/a?b=1#c'),
          Uri.parse('https://example.com/a?b=1#c'));
      expect(parseWebLink('http://example.com'), isNotNull);
    });

    test('an upper-case scheme and surrounding whitespace', () {
      expect(parseWebLink('  HTTPS://Example.com/x  '), isNotNull);
    });

    test('ports and IP hosts', () {
      expect(parseWebLink('http://192.168.1.5:8080/x'), isNotNull);
    });
  });

  group('parseWebLink refuses', () {
    test('dangerous or non-web schemes', () {
      for (final String href in <String>[
        'javascript:alert(1)',
        'intent://x#Intent;scheme=http;end',
        'file:///etc/passwd',
        'data:text/html;base64,AAAA',
        'tel:+123456789',
        'mailto:a@b.c',
        'ftp://example.com',
      ]) {
        expect(parseWebLink(href), isNull, reason: href);
      }
    });

    test('relative links, empty input, and null', () {
      for (final String? href in <String?>['/path', 'example.com', '', '   ', null]) {
        expect(parseWebLink(href), isNull, reason: '$href');
      }
    });

    test('a scheme with no host', () {
      expect(parseWebLink('https://'), isNull);
      expect(parseWebLink('https:///path'), isNull);
    });

    test('embedded credentials (a phishing pattern)', () {
      expect(parseWebLink('https://user:pass@example.com'), isNull);
      expect(parseWebLink('https://trusted.com@evil.com'), isNull);
    });
  });
}
