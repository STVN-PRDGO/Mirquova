import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/app_updates.dart';

abstract interface class PackagePlatform {
  String? get packageName;
  Future<Directory> updateDirectory();
  Future<void> openPackage(File file);
}

class NativePackagePlatform implements PackagePlatform {
  static const _channel = MethodChannel('dev.mirquova/app');

  @override
  String? get packageName => switch (Abi.current()) {
    Abi.windowsX64 => 'Mirquova-preview-windows-x64.zip',
    Abi.macosArm64 => 'Mirquova-preview-macos-arm64.zip',
    Abi.androidArm64 ||
    Abi.androidX64 => 'Mirquova-preview-android-arm64-debug.apk',
    Abi.linuxX64 => 'Mirquova-preview-linux-x64.tar.gz',
    Abi.linuxArm64 => 'Mirquova-preview-linux-arm64.tar.gz',
    _ => null,
  };

  @override
  Future<Directory> updateDirectory() async {
    final path = await _channel.invokeMethod<String>('getUpdateDirectory');
    if (path == null || path.isEmpty) {
      throw const UpdateFailure('Update storage is unavailable.');
    }
    return Directory(path);
  }

  @override
  Future<void> openPackage(File file) =>
      _channel.invokeMethod<void>('openUpdatePackage', file.path);
}

enum PackageStatus { idle, downloading, ready, opening, error }

/// Opt-in, bounded, disk-streamed downloads. No network IO at construction.
class PackageUpdates extends ChangeNotifier {
  PackageUpdates({
    PackagePlatform? platform,
    HttpClient Function()? clientFactory,
    this.timeout = const Duration(minutes: 15),
  }) : platform = platform ?? NativePackagePlatform(),
       _clientFactory = clientFactory ?? HttpClient.new;

  final PackagePlatform platform;
  final HttpClient Function() _clientFactory;
  final Duration timeout;
  PackageStatus status = PackageStatus.idle;
  String? message;
  int received = 0;
  UpdateAsset? asset;
  File? _file;
  HttpClient? _client;
  Future<void>? _pending;
  Completer<void>? _cancellation;
  int _generation = 0;
  bool _disposed = false;

  bool get busy =>
      status == PackageStatus.downloading || status == PackageStatus.opening;
  double? get progress => asset == null ? null : received / asset!.size;

  UpdateAsset? compatibleAsset(UpdateRelease release) {
    final matches = release.assets
        .where((item) => item.name == platform.packageName)
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  Future<void> download(UpdateAsset selected) {
    if (_disposed || _pending != null) return _pending ?? Future.value();
    // Validate even injected/fake release sources before any filesystem or network IO.
    final segments = selected.url.pathSegments;
    final parsed = segments.length == 6
        ? UpdateAsset.parse({
            'name': selected.name,
            'size': selected.size,
            'digest': 'sha256:${selected.sha256}',
            'state': 'uploaded',
            'browser_download_url': selected.url.toString(),
          }, segments[4])
        : null;
    if (parsed == null ||
        selected.name != platform.packageName ||
        !RegExp(r'^v?[0-9]+\.[0-9]+\.[0-9]+(?:\+[0-9]+)?$')
            .hasMatch(segments[4])) {
      status = PackageStatus.error;
      message = 'No compatible verified download is available.';
      notifyListeners();
      return Future.value();
    }
    asset = selected;
    _file = null;
    received = 0;
    message = null;
    status = PackageStatus.downloading;
    final generation = ++_generation;
    final cancellation = Completer<void>();
    _cancellation = cancellation;
    final pending = _perform(selected, generation, cancellation);
    _pending = pending;
    notifyListeners();
    return pending;
  }

  void _check(int generation) {
    if (_disposed || generation != _generation) {
      throw const UpdateFailure('Download cancelled.');
    }
  }

  Future<void> _perform(
    UpdateAsset selected,
    int generation,
    Completer<void> cancellation,
  ) async {
    // Publish the in-flight future before any synchronous adapter failure.
    await Future<void>.value();
    HttpClient? client;
    try {
      _check(generation);
      client = _clientFactory();
      _client = client;
      client.connectionTimeout = const Duration(seconds: 15);
      client.userAgent = 'Mirquova package updater';
      final file = await Future.any<File>([
        _fetch(client, selected, generation).timeout(timeout),
        cancellation.future.then<File>(
          (_) => throw const UpdateFailure('Download cancelled.'),
        ),
      ]);
      _check(generation);
      _file = file;
      status = PackageStatus.ready;
      message = 'Download verified. Ready to open.';
    } catch (error) {
      if (!_disposed && generation == _generation) {
        status = PackageStatus.error;
        message = error is UpdateFailure ? error.message : 'Download failed. Check your connection and available storage, then retry.';
      }
    } finally {
      client?.close(force: true);
      if (identical(_client, client)) _client = null;
      if (!_disposed && generation == _generation) {
        // Invalidate any worker still completing after the timeout.
        ++_generation;
        _pending = null;
        _cancellation = null;
        notifyListeners();
      }
    }
  }

  static bool allowedRedirect(Uri url) =>
      url.scheme == 'https' &&
      url.port == 443 &&
      url.userInfo.isEmpty &&
      !url.hasFragment &&
      const {
        'github.com',
        'release-assets.githubusercontent.com',
        'objects.githubusercontent.com',
      }.contains(url.host);

  Future<File> _fetch(
    HttpClient client,
    UpdateAsset selected,
    int generation,
  ) async {
    Directory? staging;
    RandomAccessFile? output;
    var keep = false;
    try {
      final root = await platform.updateDirectory();
      _check(generation);
      staging = await root.createTemp('download-');
      _check(generation);
      final partial = File('${staging.path}/${selected.name}.part');
      var url = selected.url;
      HttpClientResponse? response;
      for (var redirects = 0; redirects <= 3; redirects++) {
        _check(generation);
        final request = await client.getUrl(url);
        _check(generation);
        request.followRedirects = false;
        request.maxRedirects = 0;
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        final next = await request.close();
        _check(generation);
        if (const [301, 302, 303, 307, 308].contains(next.statusCode)) {
          final location = next.headers.value(HttpHeaders.locationHeader);
          if (location == null) {
            throw const UpdateFailure('Invalid download redirect.');
          }
          url = url.resolve(location);
          if (redirects == 3 || !allowedRedirect(url)) {
            throw const UpdateFailure(
              'The update host returned an unsupported redirect.',
            );
          }
          // Cancel the redirect body rather than buffering untrusted data.
          await next.listen((_) {}).cancel();
          continue;
        }
        response = next;
        break;
      }
      if (response == null ||
          response.statusCode != HttpStatus.ok ||
          (response.contentLength != -1 &&
              response.contentLength != selected.size)) {
        throw const UpdateFailure(
          'The update package is unavailable or its size changed. Check for updates again.',
        );
      }
      output = await partial.open(mode: FileMode.writeOnly);
      _check(generation);
      var count = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        _check(generation);
        count += chunk.length;
        if (count > selected.size) {
          throw const UpdateFailure(
            'The update package exceeded its expected size.',
          );
        }
        await output.writeFrom(chunk);
        _check(generation);
        received = count;
        notifyListeners();
      }
      await output.close();
      output = null;
      _check(generation);
      if (count != selected.size ||
          (await sha256.bind(partial.openRead()).first).toString() !=
              selected.sha256) {
        throw const UpdateFailure(
          'Package integrity check failed. The download was discarded.',
        );
      }
      _check(generation);
      final complete = await partial.rename('${staging.path}/${selected.name}');
      _check(generation);
      keep = true;
      return complete;
    } finally {
      await output?.close();
      if (!keep && staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  Future<void> open() async {
    final file = _file;
    final selected = asset;
    if (_disposed || busy || file == null || selected == null) return;
    status = PackageStatus.opening;
    message = null;
    notifyListeners();
    try {
      if (await file.length() != selected.size ||
          (await sha256.bind(file.openRead()).first).toString() !=
              selected.sha256) {
        throw const UpdateFailure(
          'The downloaded package changed. Download it again.',
        );
      }
      if (_disposed) return;
      await platform.openPackage(file);
      if (_disposed) return;
      status = PackageStatus.ready;
      message = 'Package opened. Follow the system installation steps.';
    } on PlatformException catch (error) {
      if (!_disposed) {
        status = PackageStatus.ready;
        message = error.message ?? 'Could not open the package.';
      }
    } catch (error) {
      if (!_disposed) {
        status = PackageStatus.ready;
        message = error is UpdateFailure ? error.message : 'Could not open the package. Allow installation in system settings if prompted, then try again.';
      }
    }
    if (!_disposed) notifyListeners();
  }

  void cancel() {
    if (_disposed || status != PackageStatus.downloading) return;
    ++_generation;
    _cancellation?.complete();
    _cancellation = null;
    _client?.close(force: true);
    _pending = null;
    status = PackageStatus.idle;
    message = 'Download cancelled.';
    notifyListeners();
  }

  @override
  void dispose() {
    cancel();
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
