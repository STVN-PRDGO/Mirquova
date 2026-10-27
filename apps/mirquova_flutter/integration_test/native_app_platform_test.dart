import 'dart:io';
import 'dart:ui' as ui;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mirquova/adapters/pairing_identity.dart';
import 'package:mirquova/adapters/pairing_transport.dart';
import 'package:mirquova/adapters/native_app_platform.dart';
import 'package:mirquova/adapters/native_discovery.dart';
import 'package:mirquova/app.dart';
import 'package:mirquova/core/app_updates.dart';
import 'package:mirquova/core/discovery_port.dart';
import 'package:mirquova/core/pairing_invitation.dart';

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
    debugPrint('[native-pairing-smoke] reading package metadata');
    final info = await platform.readBuildInfo().timeout(
      const Duration(seconds: 15),
    );
    expect(info.version, matches(RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+')));
    expect(info.buildNumber, matches(RegExp(r'^[0-9]+$')));

    // Exercise real OS-backed identity/pin persistence under isolated keys.
    // This never reads, overwrites, or deletes the app's normal pairing state.
    final testNamespace =
        'mirquova.pairing.integration.${DateTime.now().microsecondsSinceEpoch}';
    final identityKey = '$testNamespace.identity.v1';
    final trustKey = '$testNamespace.trusted_peers.v1';
    final pairingStore = FlutterPairingSecretStore();
    final identityApi = FfiPairingIdentityApi();
    final identityRepository = PairingIdentityRepository(
      api: identityApi,
      store: pairingStore,
      storageKey: identityKey,
    );
    final trustRepository = PairingTrustRepository(
      store: pairingStore,
      storageKey: trustKey,
    );
    debugPrint('[native-pairing-smoke] validating OS-backed identity storage');
    try {
      final generated = await identityRepository.loadOrCreate().timeout(
        const Duration(seconds: 15),
      );
      final certificate = Uint8List.fromList(generated.certificateDer);
      try {
        expect(identityApi.validate(generated), isTrue);
      } finally {
        generated.clearPrivateKeyCopy();
      }

      final restored = await identityRepository.loadOrCreate().timeout(
        const Duration(seconds: 15),
      );
      try {
        expect(identityApi.validate(restored), isTrue);
        expect(restored.certificateDer, certificate);

        await trustRepository
            .trust(alias: 'Integration probe', certificateDer: certificate)
            .timeout(const Duration(seconds: 15));
        final peers = await trustRepository.list().timeout(
          const Duration(seconds: 15),
        );
        expect(peers.single.alias, 'Integration probe');
        expect(peers.single.certificateDer, isNotEmpty);
        await trustRepository
            .revoke(peers.single.fingerprintSha256)
            .timeout(const Duration(seconds: 15));
        expect(
          await trustRepository.list().timeout(const Duration(seconds: 15)),
          isEmpty,
        );
      } finally {
        restored.clearPrivateKeyCopy();
      }
    } finally {
      await Future.wait([
        pairingStore.delete(identityKey).timeout(const Duration(seconds: 15)),
        pairingStore.delete(trustKey).timeout(const Duration(seconds: 15)),
      ]);
    }
    debugPrint('[native-pairing-smoke] identity reload and pin revoke passed');

    // Exercise the real Dart-to-Rust pairing FFI boundary: wrong host pins and
    // public bind addresses fail before network activity, then a listener is
    // opened briefly on a private interface and stopped cleanly.
    debugPrint('[native-pairing-smoke] validating pairing FFI boundaries');
    final ffiIdentity = identityApi.create();
    final pairingFfi = FfiPairingTransportApi();
    try {
      final certificateHex = _encodeHex(ffiIdentity.certificateDer);
      final invitation = jsonEncode({
        'version': 2,
        'purpose': 'pairing',
        'endpoint': {'ipv4': '192.168.1.20', 'port': 45833},
        'identity_ca_certificate_der_hex': certificateHex,
        'secret': '01' * 32,
        'ttl_seconds': 120,
      });
      expect(
        pairingFfi.startJoin(
          invitationPayload: Uint8List.fromList(utf8.encode(invitation)),
          confirmedFingerprintSha256: '00' * 32,
          alias: 'Integration probe',
          identity: ffiIdentity,
        ),
        isFalse,
      );
      expect(pairingFfi.read().status.name, 'idle');
      expect(
        () => pairingFfi.startHost(
          localIpv4: '8.8.8.8',
          port: 0,
          hostAlias: 'Integration probe',
          identity: ffiIdentity,
        ),
        throwsStateError,
      );
      expect(pairingFfi.read().status.name, 'idle');

      final address = await _privateIpv4Address();
      if (address == null) {
        debugPrint(
          '[native-pairing-smoke] no RFC1918 interface; skipping listener bind',
        );
      } else {
        final hostPayload = pairingFfi.startHost(
          localIpv4: address,
          port: 0,
          hostAlias: 'Integration probe',
          identity: ffiIdentity,
        );
        try {
          final hostInvitation = PairingInvitation.parse(hostPayload);
          expect(hostInvitation.endpoint.address, address);
          expect(hostInvitation.endpoint.port, inInclusiveRange(1, 65535));
          hostInvitation.dispose();
          expect(pairingFfi.read().status.name, 'waitingForPeer');
        } finally {
          pairingFfi.stop();
        }
        expect(pairingFfi.read().status.name, 'idle');
      }
    } finally {
      pairingFfi.stop();
      ffiIdentity.clearPrivateKeyCopy();
    }
    debugPrint('[native-pairing-smoke] pairing FFI boundaries passed');

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
    debugPrint('[native-pairing-smoke] loading native app UI');
    await _settle(tester);
    if (find.byTooltip('Open navigation menu').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('Open navigation menu'));
      await _settle(tester);
    }
    await tester.ensureVisible(find.text('Pair').first);
    await tester.tap(find.text('Pair').first);
    await _settle(tester);
    expect(find.text('Pair devices'), findsOneWidget);
    expect(find.text('Invitation text'), findsOneWidget);
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      expect(find.text('Scan QR code'), findsOneWidget);
    }
    debugPrint('[native-pairing-smoke] Pair route loaded');

    if (find.byTooltip('Open navigation menu').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('Open navigation menu'));
      await _settle(tester);
    }
    await tester.ensureVisible(find.text('Settings').first);
    await tester.tap(find.text('Settings').first);
    await _settle(tester);
    final installed = AppVersion.parse(
      info.version,
      buildNumber: info.buildNumber,
    );
    expect(find.text('Installed version: $installed'), findsOneWidget);
    await tester.ensureVisible(find.text('Check for updates'));
    await tester.tap(find.text('Check for updates'));
    await _settle(tester);
    expect(find.text('Check GitHub for updates?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
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

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 30),
);

String _encodeHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Future<String?> _privateIpv4Address() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (ManualEndpoint.parse(address.address, '1') != null) {
        return address.address;
      }
    }
  }
  return null;
}
