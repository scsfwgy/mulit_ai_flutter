import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;

bool isPublicAgentAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (b.length == 16) {
    // Accept native global unicast only; exclude transition/documentation ranges.
    return b[0] & 0xe0 == 0x20 &&
        !(b[0] == 0x20 && b[1] == 0x02) &&
        !(b[0] == 0x20 &&
            b[1] == 0x01 &&
            (b[2] < 2 || b[2] == 0x0d && b[3] == 0xb8));
  }
  return b[0] != 0 &&
      b[0] != 10 &&
      b[0] != 127 &&
      b[0] < 224 &&
      !(b[0] == 100 && b[1] >= 64 && b[1] <= 127) &&
      !(b[0] == 169 && b[1] == 254) &&
      !(b[0] == 172 && b[1] >= 16 && b[1] <= 31) &&
      !(b[0] == 192 && (b[1] == 0 || b[1] == 168)) &&
      !(b[0] == 198 &&
          (b[1] == 18 || b[1] == 19 || b[1] == 51 && b[2] == 100)) &&
      !(b[0] == 203 && b[1] == 0 && b[2] == 113);
}

Uri publicAgentUri(String value) {
  final uri = Uri.parse(value);
  if (value.length > 4096 ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      uri.host.endsWith('.') ||
      uri.host.toLowerCase() == 'localhost') {
    throw const FormatException('Public HTTPS URLs only');
  }
  final literal = InternetAddress.tryParse(
    uri.host.replaceAll(RegExp(r'[\[\]]'), ''),
  );
  if (literal != null && !isPublicAgentAddress(literal)) {
    throw const FormatException('Private address');
  }
  return uri;
}

String extractAgentWebText(String source) {
  final document = html.parse(source);
  document
      .querySelectorAll(
        'script,style,noscript,iframe,svg,nav,header,footer,form',
      )
      .forEach((e) => e.remove());
  for (final element in document.querySelectorAll('p,div,li,tr,h1,h2,h3,br')) {
    element.nodes.add(dom.Text('\n'));
  }
  return (document.body?.text ?? '')
      .replaceAll(RegExp(r'[ \t\r]+'), ' ')
      .replaceAll(RegExp(r'\n\s*\n+'), '\n\n')
      .trim();
}

class AgentWebReader {
  AgentWebReader() {
    _client.findProxy = (_) => 'DIRECT';
    _client.connectionFactory = (uri, proxyHost, proxyPort) async {
      publicAgentUri(uri.toString());
      final addresses = await InternetAddress.lookup(uri.host)
          .timeout(const Duration(seconds: 10));
      if (_cancelled ||
          addresses.isEmpty ||
          addresses.any((a) => !isPublicAgentAddress(a))) {
        throw const FormatException('Blocked address');
      }
      // Connect to the checked address, without a second DNS resolution.
      return Socket.startConnect(addresses.first, uri.port);
    };
  }
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client.close(force: true);
  }

  Future<Map<String, dynamic>> read(String value) async {
    var uri = publicAgentUri(value);
    for (var redirect = 0; redirect <= 3; redirect++) {
      if (_cancelled) throw const FormatException('Cancelled');
      final request = await _client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set('user-agent', 'AI-Link/1.0');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value('location');
        if (location == null) throw const FormatException('Missing location');
        uri = publicAgentUri(uri.resolve(location).toString());
        await response.take(0).drain<void>();
        continue;
      }
      final type = response.headers.contentType?.mimeType;
      if (response.statusCode != 200 ||
          ![
            'text/html',
            'text/plain',
            'text/markdown',
            'application/xhtml+xml',
          ].contains(type)) {
        throw const FormatException('Unreadable page');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        if (bytes.length + chunk.length > 1024 * 1024) {
          throw const FormatException('Page too large');
        }
        bytes.addAll(chunk);
      }
      final source = utf8.decode(bytes);
      final text = type == 'text/html' || type == 'application/xhtml+xml'
          ? extractAgentWebText(source)
          : source;
      if (text.trim().isEmpty) throw const FormatException('Empty page');
      return {
        'url': uri.toString(),
        'text': String.fromCharCodes(text.runes.take(10000)),
        'truncated': text.runes.length > 10000,
      };
    }
    throw const FormatException('Too many redirects');
  }
}
