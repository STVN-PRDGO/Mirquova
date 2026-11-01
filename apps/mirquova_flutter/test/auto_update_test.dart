import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/adapters/auto_update.dart';
import 'package:mirquova/adapters/package_updates.dart';
import 'package:mirquova/adapters/pairing_identity.dart';
import 'package:mirquova/core/app_updates.dart';

class _Store implements PairingSecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _PackagePlatform implements PackagePlatform {
  @override
  String get packageName => 'Mirquova-preview-windows-x64.zip';
  @override
  Future<Directory> updateDirectory() async => throw StateError('offline');
  @override
  Future<void> openPackage(File file) async => throw StateError('offline');
}

class _Packages extends PackageUpdates {
  _Packages() : super(platform: _PackagePlatform());
  int downloads = 0, opens = 0;
  bool refusePermission = false;

  @override
  Future<void> download(UpdateAsset selected) async {
    downloads++;
    asset = selected;
    status = PackageStatus.ready;
    notifyListeners();
  }

  @override
  Future<bool> open() async {
    opens++;
    needsInstallPermission = refusePermission;
    return !refusePermission;
  }
}

class _Releases implements UpdateSource {
  int calls = 0;
  String version = '0.4.0+4';
  bool fail = false;

  @override
  Future<UpdateRelease?> latest() async {
    calls++;
    if (fail) throw PlatformException(code: 'offline');
    return UpdateRelease(
      version: AppVersion.parse(version),
      pageUrl: Uri.parse(
        'https://github.com/STVN-PRDGO/Mirquova/releases/tag/v$version',
      ),
      assets: [
        UpdateAsset(
          name: 'Mirquova-preview-windows-x64.zip',
          url: Uri.parse(
            'https://github.com/STVN-PRDGO/Mirquova/releases/download/v$version/Mirquova-preview-windows-x64.zip',
          ),
          size: 1024,
          sha256: '0' * 64,
        ),
      ],
    );
  }

  @override
  void cancel() {}
}

void main() {
  late _Store store;
  late _Packages packages;
  late _Releases releases;
  late UpdateController updates;
  late DateTime now;
  late AutoUpdate auto;

  setUp(() {
    store = _Store();
    packages = _Packages();
    releases = _Releases();
    updates = UpdateController(
      currentVersion: AppVersion.parse('0.3.0', buildNumber: '3'),
      source: releases,
    );
    now = DateTime(2026, 11, 1, 9);
    auto = AutoUpdate(settings: store, packages: packages, clock: () => now);
  });

  tearDown(() {
    auto.dispose();
    updates.dispose();
    packages.dispose();
  });

  test('stays offline until the user turns it on', () async {
    await auto.load();
    await auto.run(updates, canInstall: () => true);
    expect(releases.calls, 0);
    await auto.setEnabled(true);
    expect(store.values[AutoUpdate.settingKey], 'on');
  });

  test('checks, downloads and installs a newer release', () async {
    store.values[AutoUpdate.settingKey] = 'on';
    await auto.load();
    await auto.run(updates, canInstall: () => true);
    expect(releases.calls, 1);
    expect(packages.downloads, 1);
    expect(packages.opens, 1);
    expect(auto.installPending, isFalse);
  });

  test('does nothing more when the installed version is current', () async {
    releases.version = '0.3.0+3';
    await auto.setEnabled(true);
    await auto.run(updates, canInstall: () => true);
    expect(packages.downloads, 0);
    expect(packages.opens, 0);
  });

  test('waits to install while the app is busy or hidden', () async {
    await auto.setEnabled(true);
    var allowed = false;
    await auto.run(updates, canInstall: () => allowed);
    expect(packages.downloads, 1);
    expect(packages.opens, 0);
    expect(auto.installPending, isTrue);
    allowed = true;
    await auto.installIfPending(() => allowed);
    expect(packages.opens, 1);
    expect(auto.installPending, isFalse);
  });

  test('retries after Android asks for install permission', () async {
    await auto.setEnabled(true);
    packages.refusePermission = true;
    await auto.run(updates, canInstall: () => true);
    expect(auto.installPending, isTrue);
    packages.refusePermission = false;
    await auto.installIfPending(() => true);
    expect(packages.opens, 2);
    expect(auto.installPending, isFalse);
  });

  test('checks at most every six hours unless forced', () async {
    releases.version = '0.3.0+3';
    await auto.setEnabled(true);
    await auto.run(updates, canInstall: () => true);
    await auto.run(updates, canInstall: () => true);
    expect(releases.calls, 1);
    now = now.add(const Duration(hours: 7));
    await auto.run(updates, canInstall: () => true);
    expect(releases.calls, 2);
    await auto.run(updates, canInstall: () => true, force: true);
    expect(releases.calls, 3);
  });

  test('a failed check is retried on the next run', () async {
    await auto.setEnabled(true);
    releases.fail = true;
    await auto.run(updates, canInstall: () => true);
    releases.fail = false;
    await auto.run(updates, canInstall: () => true);
    expect(releases.calls, 2);
    expect(packages.opens, 1);
  });
}
