import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mirquova/adapters/native_discovery.dart';
import 'package:mirquova/app.dart';
import 'package:mirquova/core/discovery_port.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native runner controls visibility, excludes itself and cancels scans',
    (tester) async {
      final discovery = NativeDiscovery();
      expect(
        discovery.snapshot.status,
        DiscoveryStatus.idle,
        reason: 'The native library must load and provide a real ABI snapshot.',
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MirquovaApp(discovery: discovery),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ready when you are'), findsOneWidget);
      expect(find.text('Scan nearby'), findsOneWidget);

      Future<void> waitFor(DiscoveryStatus status) async {
        final deadline = DateTime.now().add(const Duration(seconds: 12));
        while (discovery.snapshot.status != status &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(
          discovery.snapshot.status,
          status,
          reason: discovery.snapshot.message,
        );
      }

      Future<void> waitPresence(PresenceStatus status) async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (discovery.snapshot.presence.status != status &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(
          discovery.snapshot.presence.status,
          status,
          reason: discovery.snapshot.presence.message,
        );
      }

      await tester.tap(find.text('Make discoverable'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Windows preview');
      await tester.tap(find.text('Show for 2 minutes'));
      await waitPresence(PresenceStatus.visible);
      expect(find.text('Visible as Windows preview'), findsOneWidget);

      await tester.tap(find.text('Scan nearby'));
      await tester.pump();
      expect(discovery.snapshot.status, DiscoveryStatus.scanning);
      await waitFor(DiscoveryStatus.complete);
      expect(find.text('Scan complete'), findsOneWidget);
      expect(discovery.snapshot.peers.every((peer) => !peer.verified), isTrue);
      expect(
        discovery.snapshot.peers.any((peer) => peer.name == 'Windows preview'),
        isFalse,
        reason: 'The local presence announcement must not appear as a remote candidate.',
      );

      await tester.tap(find.text('Scan nearby'));
      await tester.pump();
      expect(find.text('Stop scan'), findsOneWidget);
      await tester.tap(find.text('Stop scan'));
      await waitFor(DiscoveryStatus.stopped);
      expect(find.text('Scan stopped'), findsOneWidget);

      await tester.tap(find.text('Hide now'));
      await waitPresence(PresenceStatus.hidden);
      expect(find.text('Hidden from discovery'), findsOneWidget);

      const previewPath = String.fromEnvironment('MIRQUOVA_PREVIEW_PATH');
      if (previewPath.isNotEmpty && Platform.isWindows) {
        await tester.pumpAndSettle();
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(previewPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
