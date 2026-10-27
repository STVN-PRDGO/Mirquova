import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/adapters/package_updates.dart';
import 'package:mirquova/core/app_updates.dart';

const packageName = 'Mirquova-preview-macos-arm64.zip';
final payload = utf8.encode('offline package fixture, not an installable app');
UpdateAsset fixture({String? digest, int? size, String? name}) => UpdateAsset(
  name: name ?? packageName,
  url: Uri.https(
    'github.com',
    '/STVN-PRDGO/Mirquova/releases/download/v0.4.0/${name ?? packageName}',
  ),
  size: size ?? payload.length,
  sha256: digest ?? sha256.convert(payload).toString(),
);

class MemoryPlatform implements PackagePlatform {
  MemoryPlatform(this.root);
  final Directory root;
  final opened = <File>[];
  @override
  String? get packageName => 'Mirquova-preview-macos-arm64.zip';
  @override
  Future<Directory> updateDirectory() async => root;
  @override
  Future<void> openPackage(File file) async => opened.add(file);
}

class Headers extends Fake implements HttpHeaders {
  Headers([this.location]);
  final String? location;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  String? value(String name) =>
      name == HttpHeaders.locationHeader ? location : null;
}

class Response extends Fake implements HttpClientResponse {
  Response({
    List<int>? body,
    Stream<List<int>>? stream,
    this.statusCode = 200,
    this.contentLength = -1,
    String? location,
  }) : _stream = stream ?? Stream.value(body ?? payload),
       headers = Headers(location);
  final Stream<List<int>> _stream;
  @override
  final int statusCode;
  @override
  final int contentLength;
  @override
  final HttpHeaders headers;
  @override
  Stream<List<int>> timeout(
    Duration timeLimit, {
    void Function(EventSink<List<int>>)? onTimeout,
  }) => _stream.timeout(timeLimit, onTimeout: onTimeout);
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

class Request extends Fake implements HttpClientRequest {
  Request(this.response);
  final Future<HttpClientResponse> response;
  @override
  final HttpHeaders headers = Headers();
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  Future<HttpClientResponse> close() => response;
}

class Client extends Fake implements HttpClient {
  Client(this.responses);
  final List<Future<HttpClientResponse>> responses;
  final urls = <Uri>[];
  bool closed = false;
  @override
  Duration? connectionTimeout;
  @override
  String? userAgent;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    urls.add(url);
    return Request(responses.removeAt(0));
  }

  @override
  void close({bool force = false}) => closed = true;
}

void main() {
  late Directory root;
  late MemoryPlatform platform;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('mirquova-update-test-');
    platform = MemoryPlatform(root);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'streams, checks size and digest, and opens only on explicit action',
    () async {
      final client = Client([
        Future.value(Response(contentLength: payload.length)),
      ]);
      final updates = PackageUpdates(
        platform: platform,
        clientFactory: () => client,
      );
      addTearDown(updates.dispose);
      expect(client.urls, isEmpty);
      await updates.download(fixture());
      expect(updates.status, PackageStatus.ready);
      expect(updates.progress, 1);
      expect(platform.opened, isEmpty);
      expect(client.closed, isTrue);
      await updates.open();
      expect(await platform.opened.single.readAsBytes(), payload);
      await platform.opened.single.writeAsString('tampered');
      await updates.open();
      expect(platform.opened.length, 1);
      expect(updates.message, contains('changed'));
    },
  );

  for (final mode in ['digest', 'truncated', 'oversized', 'length', 'http']) {
    test('rejects $mode and discards partial files', () async {
      final client = Client([
        Future.value(
          Response(
            body: mode == 'truncated'
                ? payload.sublist(1)
                : mode == 'oversized'
                ? [...payload, 0]
                : payload,
            contentLength: mode == 'length' ? 1000 : -1,
            statusCode: mode == 'http' ? 404 : 200,
          ),
        ),
      ]);
      final updates = PackageUpdates(
        platform: platform,
        clientFactory: () => client,
      );
      addTearDown(updates.dispose);
      await updates.download(
        fixture(digest: mode == 'digest' ? '0' * 64 : null),
      );
      expect(updates.status, PackageStatus.error);
      expect(await root.list().toList(), isEmpty);
      await updates.open();
      expect(platform.opened, isEmpty);
    });
  }

  test('follows only bounded HTTPS GitHub storage redirects', () async {
    final client = Client([
      Future.value(
        Response(
          statusCode: 302,
          location: 'https://release-assets.githubusercontent.com/asset?token=fixture',
        ),
      ),
      Future.value(Response()),
    ]);
    final updates = PackageUpdates(
      platform: platform,
      clientFactory: () => client,
    );
    addTearDown(updates.dispose);
    await updates.download(fixture());
    expect(updates.status, PackageStatus.ready);
    expect(client.urls.length, 2);
  });

  for (final location in [
    'https://evil.example/file',
    'http://github.com/file',
    'https://github.com@evil.example/file',
    'https://release-assets.githubusercontent.com:444/file',
  ]) {
    test('rejects redirect $location before contacting it', () async {
      final client = Client([
        Future.value(Response(statusCode: 302, location: location)),
      ]);
      final updates = PackageUpdates(
        platform: platform,
        clientFactory: () => client,
      );
      addTearDown(updates.dispose);
      await updates.download(fixture());
      expect(updates.status, PackageStatus.error);
      expect(client.urls.length, 1);
      expect(await root.list().toList(), isEmpty);
    });
  }

  test(
    'cancel rejects late results and permits retry without duplicate starts',
    () async {
      final gate = Completer<HttpClientResponse>();
      final client = Client([gate.future, Future.value(Response())]);
      final updates = PackageUpdates(
        platform: platform,
        clientFactory: () => client,
      );
      addTearDown(updates.dispose);
      final first = updates.download(fixture());
      expect(identical(updates.download(fixture()), first), isTrue);
      while (client.urls.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      updates.cancel();
      await first;
      gate.complete(Response());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(updates.status, PackageStatus.idle);
      expect(await root.list().toList(), isEmpty);
      await updates.download(fixture());
      expect(updates.status, PackageStatus.ready);
    },
  );

  test('whole-operation timeout cannot accept late completion', () async {
    final gate = Completer<HttpClientResponse>();
    final client = Client([gate.future]);
    final updates = PackageUpdates(
      platform: platform,
      clientFactory: () => client,
      timeout: const Duration(milliseconds: 20),
    );
    addTearDown(updates.dispose);
    await updates.download(fixture());
    expect(updates.status, PackageStatus.error);
    gate.complete(Response());
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(updates.status, PackageStatus.error);
    expect(await root.list().toList(), isEmpty);
  });

  test('adapter construction failure is visible and retryable', () async {
    var fail = true;
    final updates = PackageUpdates(
      platform: platform,
      clientFactory: () {
        if (fail) throw StateError('offline fixture factory failure');
        return Client([Future.value(Response())]);
      },
    );
    addTearDown(updates.dispose);
    await updates.download(fixture());
    expect(updates.status, PackageStatus.error);
    fail = false;
    await updates.download(fixture());
    expect(updates.status, PackageStatus.ready);
  });

  test('dispose during a request cannot produce a ready package', () async {
    final gate = Completer<HttpClientResponse>();
    final client = Client([gate.future]);
    final updates = PackageUpdates(
      platform: platform,
      clientFactory: () => client,
    );
    final operation = updates.download(fixture());
    while (client.urls.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    updates.dispose();
    await operation;
    gate.complete(Response());
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(updates.status, isNot(PackageStatus.ready));
    expect(await root.list().toList(), isEmpty);
    expect(client.closed, isTrue);
  });

  test('invalid or incompatible metadata makes no request', () async {
    final client = Client([]);
    final updates = PackageUpdates(
      platform: platform,
      clientFactory: () => client,
    );
    addTearDown(updates.dispose);
    await updates.download(fixture(name: 'Mirquova-preview-windows-x64.zip'));
    await updates.download(fixture(digest: 'invalid'));
    expect(client.urls, isEmpty);
    expect(await root.list().toList(), isEmpty);
  });

  test(
    'release assets bind name, tag, bytes and digest; ambiguity is unavailable',
    () {
      final asset = fixture();
      final metadata = <String, Object>{
        'name': asset.name,
        'size': asset.size,
        'state': 'uploaded',
        'digest': 'sha256:${asset.sha256}',
        'browser_download_url': asset.url.toString(),
      };
      expect(UpdateAsset.parse(metadata, 'v0.4.0'), isNotNull);
      expect(UpdateAsset.parse(metadata, 'v0.5.0'), isNull);
      for (final patch in [
        <String, Object>{'size': 0},
        {'size': UpdateAsset.maxBytes + 1},
        {'digest': 'sha256:invalid'},
        {'name': '../evil.apk'},
        {'state': 'new'},
        {'browser_download_url': 'https://evil.example/app.zip'},
      ]) {
        expect(UpdateAsset.parse({...metadata, ...patch}, 'v0.4.0'), isNull);
      }
      final updates = PackageUpdates(platform: platform);
      addTearDown(updates.dispose);
      expect(
        updates.compatibleAsset(
          UpdateRelease(
            version: AppVersion.parse('0.4.0'),
            pageUrl: Uri.parse('https://github.com'),
            assets: [asset, asset],
          ),
        ),
        isNull,
      );
    },
  );
}
