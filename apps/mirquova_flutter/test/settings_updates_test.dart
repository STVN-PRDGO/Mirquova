import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/app.dart';
import 'package:mirquova/adapters/package_updates.dart';
import 'package:mirquova/core/app_platform.dart';
import 'package:mirquova/core/app_updates.dart';

import 'app_test.dart' show TestDiscovery;

class _AppPlatform implements AppPlatform {
  int lookups = 0;
  bool failLookup = false;
  AppBuildInfo info = const AppBuildInfo(version: '0.2.0', buildNumber: '2');
  bool failOpening = false;
  final opened = <Uri>[];

  @override
  Future<AppBuildInfo> readBuildInfo() async {
    lookups++;
    if (failLookup) throw PlatformException(code: 'lookup_failed');
    return info;
  }

  @override
  Future<void> openReleasePage(Uri url) async {
    opened.add(url);
    if (failOpening) throw PlatformException(code: 'browser_failed');
  }
}

class _PackagePlatform implements PackagePlatform {
  @override
  String get packageName => 'Mirquova-preview-macos-arm64.zip';
  @override
  Future<Directory> updateDirectory() async =>
      throw StateError('offline widget test');
  @override
  Future<void> openPackage(File file) async =>
      throw StateError('offline widget test');
}

class _Packages extends PackageUpdates {
  _Packages() : super(platform: _PackagePlatform());
  int downloads = 0, opens = 0;
  @override
  Future<void> download(UpdateAsset selected) async {
    downloads++;
    asset = selected;
    status = PackageStatus.ready;
    message = 'Download verified. Ready to open.';
    notifyListeners();
  }

  @override
  Future<void> open() async {
    opens++;
  }
}

class _Releases implements UpdateSource {
  int calls = 0;
  int cancellations = 0;
  final requests = <Completer<UpdateRelease?>>[];

  @override
  Future<UpdateRelease?> latest() {
    calls++;
    final request = Completer<UpdateRelease?>();
    requests.add(request);
    return request.future;
  }

  @override
  void cancel() => cancellations++;
}

UpdateRelease _release([String version = '0.3.0+3']) => UpdateRelease(
  version: AppVersion.parse(version),
  pageUrl: Uri.parse(
    'https://github.com/STVN-PRDGO/Mirquova/releases/tag/v$version',
  ),
  notes: 'Fixture release notes for offline UI tests.',
  assets: [
    UpdateAsset(
      name: 'Mirquova-preview-macos-arm64.zip',
      url: Uri.parse(
        'https://github.com/STVN-PRDGO/Mirquova/releases/download/v$version/Mirquova-preview-macos-arm64.zip',
      ),
      size: 1024,
      sha256: '0' * 64,
    ),
  ],
);

void main() {
  Future<void> launch(
    WidgetTester tester,
    _Releases releases,
    _AppPlatform platform, {
    Size size = const Size(1280, 900),
    _Packages? packages,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MirquovaApp(
        discovery: TestDiscovery(),
        appPlatform: platform,
        updateSource: releases,
        packageUpdates: packages ?? _Packages(),
      ),
    );
    await tester.pumpAndSettle();
    if (find.byTooltip('Open navigation menu').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      final settings = find.descendant(
        of: find.byType(Drawer),
        matching: find.text('Settings'),
      );
      await tester.scrollUntilVisible(
        settings,
        200,
        scrollable: find
            .descendant(
              of: find.byType(Drawer),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(settings);
    } else {
      await tester.ensureVisible(find.text('Settings').first);
      await tester.tap(find.text('Settings').first);
    }
    await tester.pumpAndSettle();
  }

  Future<void> startCheck(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Check for updates'));
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'opening Settings and cancelling consent never contacts releases',
    (tester) async {
      final releases = _Releases();
      final platform = _AppPlatform();
      await launch(tester, releases, platform);
      expect(platform.lookups, 1);
      expect(find.text('Installed version: 0.2.0+2'), findsOneWidget);
      expect(releases.calls, 0);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('Check GitHub for updates?'), findsOneWidget);
      expect(releases.calls, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(releases.calls, 0);
      expect(platform.opened, isEmpty);
    },
  );

  testWidgets(
    'release downloads in app after consent and opens the local package explicitly',
    (tester) async {
      final releases = _Releases();
      final platform = _AppPlatform();
      final packages = _Packages();
      await launch(tester, releases, platform, packages: packages);
      await startCheck(tester);
      expect(releases.calls, 1);
      expect(find.text('Checking for updates...'), findsOneWidget);
      expect(find.text('Cancel check'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Check for updates'),
            )
            .onPressed,
        isNull,
      );
      releases.requests.single.complete(_release());
      await tester.pumpAndSettle();
      expect(find.text('New release available'), findsOneWidget);
      expect(find.text('Published version: 0.3.0+3'), findsOneWidget);
      expect(platform.opened, isEmpty);
      await tester.tap(find.text('What\u2019s new'));
      await tester.pumpAndSettle();
      expect(
        find.text('Fixture release notes for offline UI tests.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Download update'));
      await tester.tap(find.text('Download update'));
      await tester.pumpAndSettle();
      expect(packages.downloads, 0);
      await tester.tap(find.text('Download now'));
      await tester.pumpAndSettle();
      expect(packages.downloads, 1);
      expect(packages.opens, 0);
      await tester.ensureVisible(find.text('Open downloaded update'));
      await tester.tap(find.text('Open downloaded update'));
      await tester.pumpAndSettle();
      expect(packages.opens, 1);
      expect(platform.opened, isEmpty);
    },
  );

  testWidgets('no release, current build, and offline failure are distinct', (
    tester,
  ) async {
    final releases = _Releases();
    await launch(tester, releases, _AppPlatform());
    await startCheck(tester);
    releases.requests.last.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('No public release available'), findsOneWidget);
    expect(find.text('No newer version available'), findsNothing);

    await startCheck(tester);
    releases.requests.last.complete(_release('0.2.0+2'));
    await tester.pumpAndSettle();
    expect(find.text('No newer version available'), findsOneWidget);
    expect(find.text('Open release page'), findsNothing);

    await startCheck(tester);
    releases.requests.last.completeError(
      const UpdateFailure('Offline. Try again.'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not check for updates'), findsOneWidget);
    expect(find.text('Offline. Try again.'), findsOneWidget);
    expect(find.text('No newer version available'), findsNothing);
  });

  testWidgets(
    'cancel check discards late completion and permits a fresh check',
    (tester) async {
      final releases = _Releases();
      await launch(tester, releases, _AppPlatform());
      await startCheck(tester);
      await tester.tap(find.text('Cancel check'));
      await tester.pumpAndSettle();
      expect(releases.cancellations, 1);
      expect(find.text('Update check cancelled.'), findsOneWidget);
      releases.requests.first.complete(_release());
      await tester.pumpAndSettle();
      expect(find.text('New release available'), findsNothing);
      await startCheck(tester);
      expect(releases.calls, 2);
      releases.requests.last.complete(null);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('backgrounding cancels check without accepting its late result', (
    tester,
  ) async {
    final releases = _Releases();
    await launch(tester, releases, _AppPlatform());
    await startCheck(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(releases.cancellations, 1);
    releases.requests.single.complete(_release());
    await tester.pumpAndSettle();
    expect(find.text('New release available'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets(
    'unknown installed version blocks comparison and can be retried',
    (tester) async {
      final releases = _Releases();
      final platform = _AppPlatform()..failLookup = true;
      await launch(tester, releases, platform);
      expect(find.text('Installed version unavailable'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Check for updates'),
            )
            .onPressed,
        isNull,
      );
      expect(releases.calls, 0);
      platform.failLookup = false;
      await tester.tap(find.text('Retry version lookup'));
      await tester.pumpAndSettle();
      expect(find.text('Installed version: 0.2.0+2'), findsOneWidget);
      expect(releases.calls, 0);
    },
  );

  testWidgets(
    'cancelling package consent makes no download or browser request',
    (tester) async {
      final releases = _Releases();
      final platform = _AppPlatform();
      final packages = _Packages();
      await launch(tester, releases, platform, packages: packages);
      await startCheck(tester);
      releases.requests.single.complete(_release());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Download update'));
      await tester.tap(find.text('Download update'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(packages.downloads, 0);
      expect(platform.opened, isEmpty);
      expect(find.text('Open release page'), findsNothing);
    },
  );

  testWidgets('conflicting installed metadata keeps update checks disabled', (
    tester,
  ) async {
    final releases = _Releases();
    final platform = _AppPlatform()
      ..info = const AppBuildInfo(version: '0.2.0+2', buildNumber: '3');
    await launch(tester, releases, platform);
    expect(find.text('Installed version unavailable'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Check for updates'),
          )
          .onPressed,
      isNull,
    );
    expect(releases.calls, 0);
  });

  for (final brightness in Brightness.values) {
    for (final size in [
      const Size(375, 812),
      const Size(812, 375),
      const Size(768, 1024),
      const Size(1440, 900),
    ]) {
      testWidgets('update flow fits $brightness $size at 2x text', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final releases = _Releases();
        await launch(tester, releases, _AppPlatform(), size: size);
        expect(tester.takeException(), isNull);
        await startCheck(tester);
        expect(tester.takeException(), isNull);
        releases.requests.single.complete(_release());
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Download update'));
        expect(tester.takeException(), isNull);
        expect(find.text('New release available'), findsOneWidget);
      });
    }
  }
}
