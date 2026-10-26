import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/app_updates.dart';

/// Fetches release metadata, never a package. Construction does no network IO.
class GitHubUpdateSource implements UpdateSource {
  GitHubUpdateSource({
    HttpClient Function()? clientFactory,
    this.timeout = const Duration(seconds: 15),
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  static final endpoint = Uri.https(
    'api.github.com',
    '/repos/STVN-PRDGO/Mirquova/releases/latest',
  );
  static const maxResponseBytes = 256 * 1024;
  static const maxNotesLength = 12000;
  final HttpClient Function() _clientFactory;
  final Duration timeout;
  HttpClient? _client;
  int _generation = 0;

  @override
  Future<UpdateRelease?> latest() async {
    final generation = ++_generation;
    _client?.close(force: true);
    final client = _clientFactory();
    _client = client;
    client.connectionTimeout = const Duration(seconds: 8);
    client.userAgent = 'Mirquova update checker';
    try {
      return await _fetch(client, generation).timeout(timeout);
    } on UpdateFailure {
      rethrow;
    } on TimeoutException {
      throw const UpdateFailure(
        'The update check timed out. Check your connection and try again.',
      );
    } on FormatException {
      throw const UpdateFailure(
        'The release information is invalid. Try again later.',
      );
    } catch (_) {
      throw const UpdateFailure(
        'Could not reach GitHub. Check your connection and try again.',
      );
    } finally {
      client.close(force: true);
      if (identical(_client, client)) {
        _client = null;
        ++_generation;
      }
    }
  }

  Future<UpdateRelease?> _fetch(HttpClient client, int generation) async {
    final request = await client.getUrl(endpoint);
    if (generation != _generation) {
      request.abort();
      throw const UpdateFailure('Update check cancelled.');
    }
    request.followRedirects = false;
    request.maxRedirects = 0;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
    request.headers.set('X-GitHub-Api-Version', '2026-03-10');
    final response = await request.close();
    if (generation != _generation) {
      throw const UpdateFailure('Update check cancelled.');
    }
    if (response.statusCode == HttpStatus.notFound) {
      return null;
    }
    if (response.statusCode == HttpStatus.forbidden ||
        response.statusCode == 429) {
      throw const UpdateFailure(
        'GitHub declined this check or reached its request limit. Try again later.',
      );
    }
    if (response.statusCode != HttpStatus.ok) {
      throw const UpdateFailure(
        'The update service is unavailable. Try again later.',
      );
    }
    if (response.contentLength > maxResponseBytes) {
      throw const FormatException('Release response is too large.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (generation != _generation) {
        throw const UpdateFailure('Update check cancelled.');
      }
      if (bytes.length + chunk.length > maxResponseBytes) {
        throw const FormatException('Release response is too large.');
      }
      bytes.add(chunk);
    }
    return parseRelease(utf8.decode(bytes.takeBytes()));
  }

  /// Parses untrusted GitHub metadata. Release notes remain plain text.
  static UpdateRelease parseRelease(String json) {
    final value = jsonDecode(json);
    if (value is! Map<String, dynamic> ||
        value['draft'] != false ||
        value['prerelease'] != false ||
        value['tag_name'] is! String ||
        value['html_url'] is! String ||
        (value['body'] != null && value['body'] is! String)) {
      throw const FormatException('Expected a published stable release.');
    }
    final tag = value['tag_name'] as String;
    final version = AppVersion.parse(tag);
    final url = Uri.parse(value['html_url'] as String);
    final segments = url.pathSegments;
    if (url.scheme != 'https' ||
        url.host != 'github.com' ||
        url.port != 443 ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment ||
        segments.length != 5 ||
        segments[0] != 'STVN-PRDGO' ||
        segments[1] != 'Mirquova' ||
        segments[2] != 'releases' ||
        segments[3] != 'tag' ||
        segments[4] != tag) {
      throw const FormatException('Unexpected release page.');
    }
    var notes = (value['body'] as String? ?? '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(
          RegExp(
            r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F\u202A-\u202E\u2066-\u2069]',
          ),
          '',
        )
        .trim();
    if (notes.length > maxNotesLength) {
      notes = '${notes.substring(0, maxNotesLength)}\n…';
    }
    return UpdateRelease(
      version: version,
      pageUrl: Uri.https(
        'github.com',
        '/STVN-PRDGO/Mirquova/releases/tag/$tag',
      ),
      notes: notes,
    );
  }

  @override
  void cancel() {
    ++_generation;
    _client?.close(force: true);
    _client = null;
  }
}
