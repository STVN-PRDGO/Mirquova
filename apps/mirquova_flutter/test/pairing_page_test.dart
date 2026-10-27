import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/adapters/pairing_identity.dart';
import 'package:mirquova/adapters/pairing_transport.dart';
import 'package:mirquova/features/pairing/pairing_page.dart';

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

  Widget page() => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: PairingPage(controller: controller)),
    ),
  );

  Future<void> readInvitation(WidgetTester tester) async {
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Read invitation'),
    );
    expect(button.onPressed, isNotNull);
    button.onPressed!.call();
    await tester.pump();
  }

  testWidgets('host invitation shows a QR code and comparison fingerprint', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    await tester.pump();
    await tester.tap(find.text('Create invitation'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Your SHA-256 fingerprint (compare with the other device):'),
      findsOneWidget,
    );
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('Stop invitation'), findsOneWidget);
  });

  testWidgets('hiding the app stops pairing and clears the host invitation', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    await tester.pump();
    await tester.tap(find.text('Create invitation'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Stop invitation'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(transport.stopped, isTrue);
    expect(find.text('Stop invitation'), findsNothing);
    expect(
      find.text('Pairing stopped while Mirquova was hidden.'),
      findsOneWidget,
    );
  });

  testWidgets('hiding the app clears a join invitation and fingerprint', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    final invitationField = find.widgetWithText(TextField, 'Invitation text');
    await tester.enterText(invitationField, _invitation);
    await readInvitation(tester);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(find.byType(CheckboxListTile), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();

    expect(transport.stopped, isTrue);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Verify and request pairing'),
      findsNothing,
    );
    expect(tester.widget<TextField>(invitationField).controller!.text, isEmpty);
    expect(
      find.text('Pairing stopped while Mirquova was hidden.'),
      findsOneWidget,
    );
  });

  testWidgets('joining requires explicit fingerprint confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    await tester.enterText(
      find.widgetWithText(TextField, 'Invitation text'),
      _invitation,
    );
    await readInvitation(tester);

    final request = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Verify and request pairing'),
    );
    expect(request.onPressed, isNull);
    expect(find.text('Host fingerprint (SHA-256)'), findsOneWidget);

    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    final confirmedRequest = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Verify and request pairing'),
    );
    expect(confirmedRequest.onPressed, isNotNull);

    await tester.ensureVisible(find.text('Verify and request pairing'));
    await tester.tap(find.text('Verify and request pairing'));
    await tester.pump();
    await tester.pump();

    expect(utf8.decode(transport.joinedPayload!), _invitation);
    expect(transport.joinedFingerprint, isNotEmpty);
    expect(find.text('Connecting securely…'), findsOneWidget);
  });

  testWidgets('editing an invitation clears its fingerprint confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    final invitationField = find.widgetWithText(TextField, 'Invitation text');
    await tester.enterText(invitationField, '$_invitation ');
    await readInvitation(tester);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Verify and request pairing'),
          )
          .onPressed,
      isNotNull,
    );

    await tester.enterText(invitationField, '$_invitation ');
    await tester.pump();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Verify and request pairing'),
      findsNothing,
    );
  });

  testWidgets('expired join invitation clears its fingerprint confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    final invitationField = find.widgetWithText(TextField, 'Invitation text');
    await tester.enterText(
      invitationField,
      _invitation.replaceFirst('"ttl_seconds":120', '"ttl_seconds":1'),
    );
    await readInvitation(tester);

    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Verify and request pairing'),
          )
          .onPressed,
      isNotNull,
    );

    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('Invitation expired. Read a current invitation to pair.'),
      findsOneWidget,
    );
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Verify and request pairing'),
      findsNothing,
    );
  });
}
