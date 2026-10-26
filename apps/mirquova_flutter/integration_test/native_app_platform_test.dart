import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mirquova/adapters/native_app_platform.dart';
import 'package:mirquova/adapters/native_discovery.dart';
import 'package:mirquova/app.dart';
import 'package:mirquova/core/app_updates.dart';
import 'package:mirquova/core/discovery_port.dart';

class _NoNetworkUpdates implements UpdateSource {
  int requests = 0;

  @override
  Future<UpdateRelease?> latest() async {
    requests++;
    throw StateError('The native bridge test must never request releases.');
  }

  @override
  void cancel() {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native package metadata and release URL boundary', (
    tester,
  ) async {
    const platform = NativeAppPlatform();
    final info = await platform.readBuildInfo();
    expect(info.version, matches(RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+')));
    expect(info.buildNumber, matches(RegExp(r'^[0-9]+$')));

    final updates = _NoNetworkUpdates();
    final discovery = NativeDiscovery();
    expect(
      discovery.snapshot.status,
      DiscoveryStatus.idle,
      reason: 'The bundled native core must load through its default platform path.',
    );
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MirquovaApp(discovery: discovery, updateSource: updates),
      ),
    );
    await tester.pumpAndSettle();
    if (find.byTooltip('Open navigation menu').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('Settings').first);
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    final installed = AppVersion.parse(
      info.version,
      buildNumber: info.buildNumber,
    );
    expect(find.text('Installed version: $installed'), findsOneWidget);
    await tester.ensureVisible(find.text('Check for updates'));
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.text('Check GitHub for updates?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(updates.requests, 0);

    // Call the platform channel directly to verify its independent validation.
    // Every URL is invalid, so this test never launches a browser or uses a network.
    const channel = MethodChannel('dev.mirquova/app');
    for (final url in [
      'http://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0',
      'https://github.com.evil.test/STVN-PRDGO/Mirquova/releases/tag/v0.3.0',
      'https://github.com:443/STVN-PRDGO/Mirquova/releases/tag/v0.3.0',
      'https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0?next=evil',
      'https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0%2Fevil',
      'https://github.com/STVN-PRDGO/Mirquova/releases/download/v0.3.0/app.exe',
    ]) {
      await expectLater(
        channel.invokeMethod<void>('openReleasePage', url),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'invalid_release_url',
          ),
        ),
      );
    }

    const previewPath = String.fromEnvironment('MIRQUOVA_UPDATE_PREVIEW_PATH');
    if (previewPath.isNotEmpty && Platform.isWindows) {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(previewPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
