import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/adapters/pairing_identity.dart';
import 'package:mirquova/adapters/pairing_transport.dart';
import 'package:mirquova/core/discovery_port.dart';
import 'package:mirquova/features/pairing/pairing_page.dart';
import 'package:mirquova/theme.dart';

class _Store implements PairingSecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _Identity implements PairingIdentityApi {
  @override
  PairingIdentityMaterial create() => PairingIdentityMaterial(
    certificateDer: [1, 2, 3],
    privateKeyPkcs8Der: [4, 5, 6],
  );
  @override
  bool validate(PairingIdentityMaterial identity) => true;
}

class _Transport implements PairingTransportApi {
  PairingSnapshot snapshot = const PairingSnapshot();
  bool stopped = false;
  Uint8List? joinedPayload;
  String? joinedFingerprint;
  @override
  String startHost({
    required String localIpv4,
    required int port,
    required String hostAlias,
    required PairingIdentityMaterial identity,
  }) => jsonEncode({
    'version': 2,
    'purpose': 'pairing',
    'endpoint': {'ipv4': localIpv4, 'port': 45833},
    'identity_ca_certificate_der_hex': '3000',
    'secret': List.filled(64, '1').join(),
    'ttl_seconds': 120,
  });
  @override
  bool startJoin({
    required Uint8List invitationPayload,
    required String confirmedFingerprintSha256,
    required String alias,
    required PairingIdentityMaterial identity,
  }) {
    joinedPayload = Uint8List.fromList(invitationPayload);
    joinedFingerprint = confirmedFingerprintSha256;
    snapshot = const PairingSnapshot(status: PairingStatus.connecting);
    return true;
  }

  @override
  PairingSnapshot read() => snapshot;
  @override
  bool approve() => true;
  @override
  bool reject() => true;
  @override
  void stop() => stopped = true;
}

const _invitation =
    '{"version":2,"purpose":"pairing","endpoint":{"ipv4":"192.168.1.20","port":45833},"identity_ca_certificate_der_hex":"3000","secret":"1111111111111111111111111111111111111111111111111111111111111111","ttl_seconds":120}';

void main() {
  late _Store store;
  late _Transport transport;
  late PairingController controller;

  setUp(() {
    store = _Store();
    transport = _Transport();
    controller = PairingController(
      identities: PairingIdentityRepository(api: _Identity(), store: store),
      trustedPeers: PairingTrustRepository(store: store),
      api: transport,
      privateIpv4AddressProvider: () async => ['192.168.1.20'],
    );
  });

  tearDown(() => controller.dispose());

  Widget pageWithPeer({
    required Future<String> Function(List<String> addresses) fetchOffer,
  }) {
    final discovery = _Discovery(
      const DiscoverySnapshot(
        peers: [
          PeerCandidate(
            id: 'kitchen',
            name: 'Kitchen',
            addresses: ['192.168.1.9'],
            port: 0,
          ),
        ],
      ),
    );
    addTearDown(discovery.dispose);
    return MaterialApp(
      theme: mirquovaTheme(Brightness.dark),
      home: Scaffold(
        body: SingleChildScrollView(
          child: PairingPage(
            controller: controller,
            discovery: discovery,
            fetchOffer: fetchOffer,
          ),
        ),
      ),
    );
  }

  Widget page() => MaterialApp(
    theme: mirquovaTheme(Brightness.light),
    home: Scaffold(
      body: SingleChildScrollView(child: PairingPage(controller: controller)),
    ),
  );

  for (final brightness in Brightness.values) {
    for (final width in [375.0, 1024.0]) {
      testWidgets(
        'pairing layout at $width with 2x text in ${brightness.name}',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 812));
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(() => tester.binding.setSurfaceSize(null));
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(
            MaterialApp(
              theme: mirquovaTheme(brightness),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: PairingPage(controller: controller),
                ),
              ),
            ),
          );
          // Let the secure-store future finish outside the fake frame clock.
          await tester.runAsync(() async {
            await Future<void>.delayed(Duration.zero);
          });
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Scan'));
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          expect(find.text('Invitation text'), findsNothing);
          await tester.ensureVisible(find.text('No devices are trusted yet.'));
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  Future<void> scan(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Scan'));
    await tester.tap(find.text('Scan'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('scan readies this device without an invitation form', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    await tester.pump();
    await scan(tester);
    expect(find.textContaining('This device is ready'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Invitation text'), findsNothing);
    expect(find.text('Scan QR code'), findsNothing);
  });

  testWidgets('corrupt identity recovery requires a clear user confirmation', (
    tester,
  ) async {
    const key = 'mirquova.pairing.identity.v1';
    store.values[key] = '{broken';
    await tester.pumpWidget(page());
    await tester.pump();

    await scan(tester);
    expect(find.text('Reset corrupt pairing identity'), findsOneWidget);
    expect(store.values[key], '{broken');

    await tester.ensureVisible(find.text('Reset corrupt pairing identity'));
    await tester.tap(find.text('Reset corrupt pairing identity'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Reset this device identity?'), findsOneWidget);
    expect(
      find.textContaining('Devices that trusted the old identity'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(store.values[key], '{broken');

    await tester.ensureVisible(find.text('Reset corrupt pairing identity'));
    await tester.tap(find.text('Reset corrupt pairing identity'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Reset identity and continue'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(store.values.containsKey(key), isFalse);
    expect(find.text('Reset corrupt pairing identity'), findsNothing);

    await scan(tester);
    expect(store.values.containsKey(key), isTrue);
    expect(find.textContaining('This device is ready'), findsOneWidget);
  });

  testWidgets('hiding the app stops pairing', (tester) async {
    await tester.pumpWidget(page());
    await tester.pump();
    await scan(tester);
    expect(find.textContaining('This device is ready'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(transport.stopped, isTrue);
    expect(find.textContaining('This device is ready'), findsNothing);
    expect(
      find.text('Pairing stopped while Mirquova was hidden.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping a nearby device requests pairing', (tester) async {
    await tester.pumpWidget(pageWithPeer(fetchOffer: (_) async => _invitation));
    await tester.pump();
    await tester.tap(find.text('Kitchen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(utf8.decode(transport.joinedPayload!), _invitation);
    expect(transport.joinedFingerprint, isNotEmpty);
    expect(find.text('Connecting securely…'), findsOneWidget);
    expect(
      find.textContaining('Waiting for Kitchen to approve'),
      findsOneWidget,
    );
  });

  testWidgets('an unreachable device is not treated as connected', (
    tester,
  ) async {
    await tester.pumpWidget(
      pageWithPeer(
        fetchOffer: (_) async => throw const SocketException('down'),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Kitchen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Connect to Kitchen'), findsOneWidget);
    expect(find.textContaining('Could not reach Kitchen'), findsOneWidget);
    expect(transport.joinedPayload, isNull);
  });
}

class _Discovery extends DiscoveryPort {
  _Discovery(this._snapshot);
  final DiscoverySnapshot _snapshot;
  @override
  DiscoverySnapshot get snapshot => _snapshot;
  @override
  Future<void> start() async {}
  @override
  void stop() {}
  @override
  Future<void> makeDiscoverable(String alias) async {}
  @override
  void hide() {}
}
