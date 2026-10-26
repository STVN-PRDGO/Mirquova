import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/adapters/github_updates.dart';
import 'package:mirquova/core/app_updates.dart';

Map<String, Object?> _metadata({String tag = 'v0.3.0+3'}) => {
  'tag_name': tag,
  'html_url': 'https://github.com/STVN-PRDGO/Mirquova/releases/tag/$tag',
  'draft': false,
  'prerelease': false,
  'body': 'Example release notes from a fixture.',
};

class _Headers extends Fake implements HttpHeaders {
  final values = <String, Object>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value;
  }
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.response);
  final Future<HttpClientResponse> response;
  @override
  final _Headers headers = _Headers();
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  int closes = 0;
  bool aborted = false;

  @override
  Future<HttpClientResponse> close() {
    closes++;
    return response;
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) => aborted = true;
}

class _Response extends Fake implements HttpClientResponse {
  _Response({
    this.statusCode = 200,
    this.contentLength = -1,
    required this._body,
  });

  factory _Response.json(Object? json, {int status = 200}) => _Response(
    statusCode: status,
    body: Stream<List<int>>.value(utf8.encode(jsonEncode(json))),
  );

  @override
  final int statusCode;
  @override
  final int contentLength;
  final Stream<List<int>> _body;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

class _Client extends Fake implements HttpClient {
  _Client(this.request);
  final Future<HttpClientRequest> request;
  Uri? requestedUrl;
  bool forceClosed = false;
  @override
  Duration? connectionTimeout;
  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    requestedUrl = url;
    return request;
  }

  @override
  void close({bool force = false}) => forceClosed = force;
}

void main() {
  test(
    'release parser validates stable version and canonicalizes its page',
    () {
      final metadata = _metadata();
      metadata['html_url'] =
          'https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0%2B3';
      final release = GitHubUpdateSource.parseRelease(jsonEncode(metadata));
      expect(release.version.toString(), '0.3.0+3');
      expect(release.pageUrl.pathSegments.last, 'v0.3.0+3');
      expect(release.notes, contains('fixture'));
    },
  );

  test('release parser rejects redirects to unrelated or malformed pages', () {
    for (final url in [
      'http://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0+3',
      'https://github.com.evil.invalid/STVN-PRDGO/Mirquova/releases/tag/v0.3.0+3',
      'https://github.com:444/STVN-PRDGO/Mirquova/releases/tag/v0.3.0+3',
      'https://user@github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0+3',
      'https://github.com/STVN-PRDGO/Other/releases/tag/v0.3.0+3',
      'https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.4.0',
      'https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0+3/file',
      'https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0+3?download=1',
      'https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0+3#extra',
      'https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0%2Ffile',
    ]) {
      expect(
        () => GitHubUpdateSource.parseRelease(
          jsonEncode(_metadata()..['html_url'] = url),
        ),
        throwsFormatException,
        reason: url,
      );
    }
  });

  test('drafts, prereleases and malformed metadata cannot become updates', () {
    for (final metadata in [
      _metadata()..['draft'] = true,
      _metadata()..['prerelease'] = true,
      _metadata(tag: 'v0.3.0-beta'),
      _metadata()..remove('draft'),
      _metadata()..['body'] = {'html': 'unexpected'},
      _metadata()..['tag_name'] = 3,
      <String, Object?>{},
    ]) {
      expect(
        () => GitHubUpdateSource.parseRelease(jsonEncode(metadata)),
        throwsFormatException,
      );
    }
    expect(() => GitHubUpdateSource.parseRelease('[]'), throwsFormatException);
  });

  test(
    'release notes are bounded plain text with direction controls removed',
    () {
      final metadata = _metadata()
        ..['body'] = '\u202e<script>fixture</script>\u0000\r\n${'x' * 13000}';
      final release = GitHubUpdateSource.parseRelease(jsonEncode(metadata));
      expect(release.notes.startsWith('<script>fixture</script>\n'), isTrue);
      expect(release.notes.contains('\u202e'), isFalse);
      expect(release.notes.contains('\u0000'), isFalse);
      expect(release.notes.length, lessThanOrEqualTo(12002));
    },
  );

  test(
    'HTTPS client is created only by an explicit check and always closed',
    () async {
      final request = _Request(Future.value(_Response.json(_metadata())));
      final client = _Client(Future.value(request));
      var clients = 0;
      final source = GitHubUpdateSource(
        clientFactory: () {
          clients++;
          return client;
        },
      );
      expect(clients, 0);
      final release = await source.latest();
      expect(clients, 1);
      expect(release?.version.toString(), '0.3.0+3');
      expect(client.requestedUrl, GitHubUpdateSource.endpoint);
      expect(client.userAgent, 'Mirquova update checker');
      expect(client.connectionTimeout, const Duration(seconds: 8));
      expect(request.followRedirects, isFalse);
      expect(request.maxRedirects, 0);
      expect(request.headers.values['accept'], 'application/vnd.github+json');
      expect(request.headers.values['x-github-api-version'], '2026-03-10');
      expect(client.forceClosed, isTrue);
    },
  );

  test(
    '404 means no published release, without parsing an error body',
    () async {
      final request = _Request(
        Future.value(_Response.json({'message': 'Not found'}, status: 404)),
      );
      final client = _Client(Future.value(request));
      final source = GitHubUpdateSource(clientFactory: () => client);
      expect(await source.latest(), isNull);
      expect(client.forceClosed, isTrue);
    },
  );

  for (final status in [301, 302, 403, 429, 500]) {
    test('HTTP $status fails safely without following redirects', () async {
      final request = _Request(
        Future.value(
          _Response.json({'secret': 'not displayed'}, status: status),
        ),
      );
      final client = _Client(Future.value(request));
      final source = GitHubUpdateSource(clientFactory: () => client);
      await expectLater(
        source.latest(),
        throwsA(
          isA<UpdateFailure>().having(
            (error) => error.message,
            'message',
            isNot(contains('secret')),
          ),
        ),
      );
      expect(request.followRedirects, isFalse);
      expect(client.forceClosed, isTrue);
    });
  }

  test(
    'advertised and streamed response sizes are independently bounded',
    () async {
      for (final response in [
        _Response(
          contentLength: GitHubUpdateSource.maxResponseBytes + 1,
          body: const Stream.empty(),
        ),
        _Response(
          body: Stream.fromIterable([
            List<int>.filled(GitHubUpdateSource.maxResponseBytes, 32),
            [32],
          ]),
        ),
      ]) {
        final request = _Request(Future.value(response));
        final client = _Client(Future.value(request));
        final source = GitHubUpdateSource(clientFactory: () => client);
        await expectLater(source.latest(), throwsA(isA<UpdateFailure>()));
        expect(client.forceClosed, isTrue);
      }
    },
  );

  test('invalid UTF-8 and JSON fail safely', () async {
    for (final body in [
      <int>[255],
      utf8.encode('{broken'),
    ]) {
      final request = _Request(
        Future.value(_Response(body: Stream.value(body))),
      );
      final client = _Client(Future.value(request));
      final source = GitHubUpdateSource(clientFactory: () => client);
      await expectLater(source.latest(), throwsA(isA<UpdateFailure>()));
      expect(client.forceClosed, isTrue);
    }
  });

  test(
    'timeout closes the client and aborts a late request before sending',
    () async {
      final delayedRequest = Completer<HttpClientRequest>();
      final client = _Client(delayedRequest.future);
      final source = GitHubUpdateSource(
        clientFactory: () => client,
        timeout: const Duration(milliseconds: 5),
      );
      await expectLater(
        source.latest(),
        throwsA(
          isA<UpdateFailure>().having(
            (error) => error.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      expect(client.forceClosed, isTrue);
      final request = _Request(Future.value(_Response.json(_metadata())));
      delayedRequest.complete(request);
      await Future<void>.delayed(Duration.zero);
      expect(request.aborted, isTrue);
      expect(request.closes, 0);
    },
  );

  test('cancel closes the client and ignores an unsent late request', () async {
    final delayedRequest = Completer<HttpClientRequest>();
    final client = _Client(delayedRequest.future);
    final source = GitHubUpdateSource(clientFactory: () => client);
    final check = source.latest();
    source.cancel();
    final request = _Request(Future.value(_Response.json(_metadata())));
    delayedRequest.complete(request);
    await expectLater(check, throwsA(isA<UpdateFailure>()));
    expect(client.forceClosed, isTrue);
    expect(request.aborted, isTrue);
    expect(request.closes, 0);
  });
}
