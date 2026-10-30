import 'dart:convert';
import 'dart:io';

import '../core/open_subtitles.dart';

class IoOpenSubtitleTransport implements OpenSubtitleTransport {
  @override
  Future<String> get(Uri uri, Map<String, String> headers) =>
      _request('GET', uri, headers, null);

  @override
  Future<String> post(Uri uri, Map<String, String> headers, String body) =>
      _request('POST', uri, headers, body);

  @override
  Future<String> download(Uri uri) async {
    if (uri.scheme != 'https') {
      throw const FormatException('Subtitle download link was rejected.');
    }
    return _request('GET', uri, const {'Accept': 'text/plain'}, null);
  }

  Future<String> _request(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    final client = HttpClient();
    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 20));
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      if (body != null) request.add(utf8.encode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final bytes = await response
          .fold<List<int>>(<int>[], (collected, chunk) {
            if (collected.length + chunk.length > 1024 * 1024) {
              throw const FormatException('Subtitle response is too large.');
            }
            collected.addAll(chunk);
            return collected;
          })
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const FormatException(
          'OpenSubtitles refused the API key. No subtitle was saved.',
        );
      }
      if (response.statusCode == 429) {
        throw const FormatException(
          'OpenSubtitles rate limit was reached. No retry was sent.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const FormatException(
          'OpenSubtitles did not return a subtitle result.',
        );
      }
      return utf8.decode(bytes);
    } on OpenSubtitlesDisabled {
      rethrow;
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException(
        'Online subtitles are unavailable. Local subtitles still work.',
      );
    } finally {
      client.close(force: true);
    }
  }
}
