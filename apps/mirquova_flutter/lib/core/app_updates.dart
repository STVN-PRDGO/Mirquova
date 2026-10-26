import 'dart:async';

import 'package:flutter/foundation.dart';

/// Stable app versions only. Build numbers are compared when both are known.
@immutable
class AppVersion {
  const AppVersion._(this.major, this.minor, this.patch, this.build);

  final int major;
  final int minor;
  final int patch;
  final int? build;

  factory AppVersion.parse(String version, {String? buildNumber}) {
    final match = RegExp(
      r'^v?(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})(?:\+(0|[1-9][0-9]{0,17}))?$',
    ).firstMatch(version);
    if (match == null ||
        (buildNumber != null &&
            !RegExp(r'^(0|[1-9][0-9]{0,17})$').hasMatch(buildNumber))) {
      throw const FormatException('Unsupported stable app version.');
    }
    final embeddedBuild = match.group(4);
    if (embeddedBuild != null &&
        buildNumber != null &&
        embeddedBuild != buildNumber) {
      throw const FormatException('Conflicting app build numbers.');
    }
    return AppVersion._(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.tryParse(buildNumber ?? embeddedBuild ?? ''),
    );
  }

  String get semanticVersion => '$major.$minor.$patch';

  bool isNewerThan(AppVersion installed) {
    for (final components in [
      (major, installed.major),
      (minor, installed.minor),
      (patch, installed.patch),
    ]) {
      if (components.$1 != components.$2) {
        return components.$1 > components.$2;
      }
    }
    // A plain tag does not claim to identify a particular build.
    return build != null &&
        installed.build != null &&
        build! > installed.build!;
  }

  @override
  String toString() =>
      build == null ? semanticVersion : '$semanticVersion+$build';
}

@immutable
class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.pageUrl,
    this.notes = '',
  });

  final AppVersion version;
  final Uri pageUrl;
  final String notes;
}

abstract interface class UpdateSource {
  /// Called only following an explicit update check; null means no release.
  Future<UpdateRelease?> latest();
  void cancel();
}

class UpdateFailure implements Exception {
  const UpdateFailure(this.message);
  final String message;
}

enum UpdateStatus { idle, checking, upToDate, available, noRelease, error }

class UpdateController extends ChangeNotifier {
  UpdateController({required this.currentVersion, required this._source});

  final AppVersion currentVersion;
  final UpdateSource _source;
  UpdateStatus _status = UpdateStatus.idle;
  UpdateRelease? _release;
  DateTime? _lastChecked;
  String? _message;
  Future<void>? _pending;
  Completer<void>? _cancelSignal;
  int _attempt = 0;
  bool _disposed = false;

  UpdateStatus get status => _status;
  UpdateRelease? get release => _release;

  /// Time of the last successful service response, never a failed attempt.
  DateTime? get lastChecked => _lastChecked;
  String? get message => _message;

  Future<void> check() {
    if (_disposed) {
      return Future<void>.value();
    }
    if (_pending != null) {
      return _pending!;
    }
    final attempt = ++_attempt;
    final cancellation = Completer<void>();
    _cancelSignal = cancellation;
    _status = UpdateStatus.checking;
    _release = null;
    _message = null;
    // Publish the pending future before notifying listeners to prevent reentry.
    final pending = _perform(attempt, cancellation);
    _pending = pending;
    notifyListeners();
    return pending;
  }

  Future<void> _perform(int attempt, Completer<void> cancellation) async {
    try {
      final result = await Future.any<UpdateRelease?>([
        Future<UpdateRelease?>.sync(_source.latest),
        cancellation.future.then<UpdateRelease?>(
          (_) => throw const _CheckCancelled(),
        ),
      ]);
      if (_disposed || attempt != _attempt) {
        return;
      }
      _lastChecked = DateTime.now();
      _release = result;
      if (result == null) {
        _status = UpdateStatus.noRelease;
        _message = 'No published stable release is available yet.';
      } else if (result.version.isNewerThan(currentVersion)) {
        _status = UpdateStatus.available;
      } else {
        _status = UpdateStatus.upToDate;
        _message = 'You have the latest published version or a newer build.';
      }
    } catch (error) {
      if (_disposed || attempt != _attempt) {
        return;
      }
      _status = UpdateStatus.error;
      _message = error is UpdateFailure
          ? error.message
          : 'Could not check for updates. Check your connection and try again.';
    } finally {
      if (!_disposed && attempt == _attempt) {
        _pending = null;
        _cancelSignal = null;
        notifyListeners();
      }
    }
  }

  void cancel() {
    if (_disposed || _status != UpdateStatus.checking) {
      return;
    }
    ++_attempt;
    _cancelSignal?.complete();
    _cancelSignal = null;
    _pending = null;
    _source.cancel();
    _status = UpdateStatus.idle;
    _release = null;
    _message = 'Update check cancelled.';
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_attempt;
    _cancelSignal?.complete();
    _cancelSignal = null;
    _source.cancel();
    super.dispose();
  }
}

class _CheckCancelled implements Exception {
  const _CheckCancelled();
}
