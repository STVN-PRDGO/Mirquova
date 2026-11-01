import 'package:flutter/foundation.dart';

import '../core/app_updates.dart';
import 'package_updates.dart';
import 'pairing_identity.dart' show PairingSecretStore;

/// Opt-in background updates. Nothing contacts GitHub until the user turns
/// this on; afterwards each launch checks, downloads and opens the installer.
class AutoUpdate extends ChangeNotifier {
  AutoUpdate({
    required this.settings,
    required this.packages,
    this.beforeInstall,
    this.recheckAfter = const Duration(hours: 6),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const settingKey = 'mirquova.updates.auto.v1';

  final PairingSecretStore settings;
  final PackageUpdates packages;

  /// Tells the user what is about to happen, for example that Windows
  /// restarts Mirquova, before the installer starts.
  Future<void> Function()? beforeInstall;
  final Duration recheckAfter;
  final DateTime Function() _clock;

  bool _enabled = false;
  bool _running = false;
  DateTime? _lastRun;

  /// The installer could not open yet (background, busy, or waiting for the
  /// Android permission); retry when the app is in front again.
  bool installPending = false;

  bool get enabled => _enabled;
  bool get running => _running;

  Future<void> load() async {
    try {
      _enabled = await settings.read(settingKey) == 'on';
    } on Object {
      _enabled = false;
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (!value) installPending = false;
    notifyListeners();
    try {
      await settings.write(settingKey, value ? 'on' : 'off');
    } on Object {
      // The choice still applies for this session.
    }
  }

  /// [canInstall] is false while the app is hidden or a transfer is running;
  /// the install then waits for [installIfPending].
  Future<void> run(
    UpdateController updates, {
    required bool Function() canInstall,
    bool force = false,
  }) async {
    if (!_enabled || _running) return;
    final last = _lastRun;
    if (!force && last != null && _clock().difference(last) < recheckAfter) {
      return;
    }
    _running = true;
    notifyListeners();
    try {
      await updates.check();
      // A cancelled or failed check (for example, the app was hidden) is
      // retried on the next resume instead of waiting for [recheckAfter].
      if (!const {
        UpdateStatus.available,
        UpdateStatus.upToDate,
        UpdateStatus.noRelease,
      }.contains(updates.status)) {
        return;
      }
      _lastRun = _clock();
      final release = updates.release;
      if (updates.status != UpdateStatus.available || release == null) return;
      final asset = packages.compatibleAsset(release);
      if (asset == null) return;
      final downloaded =
          packages.status == PackageStatus.ready &&
          packages.asset?.url == asset.url;
      if (!downloaded) {
        await packages.download(asset);
        if (packages.status != PackageStatus.ready) {
          _lastRun = null;
          return;
        }
      }
      installPending = true;
      await installIfPending(canInstall);
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Future<void> installIfPending(bool Function() canInstall) async {
    if (!_enabled || !installPending || !canInstall()) return;
    if (packages.status != PackageStatus.ready) {
      installPending = false;
      return;
    }
    installPending = false;
    await beforeInstall?.call();
    final opened = await packages.open();
    installPending = !opened && packages.needsInstallPermission;
    notifyListeners();
  }
}
