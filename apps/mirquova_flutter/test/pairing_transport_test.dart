import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/adapters/pairing_identity.dart';
import 'package:mirquova/adapters/pairing_transport.dart';
import 'package:mirquova/core/pairing_invitation.dart';

class _Store implements PairingSecretStore {
  final values = <String, String>{};
  int writes = 0;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    writes++;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _FailingWriteStore extends _Store {
  bool failWrites = true;

  @override
  Future<void> write(String key, String value) async {
    writes++;
    if (failWrites) throw StateError('Secure storage is unavailable.');
    values[key] = value;
  }
}

class _DelayedReadStore extends _Store {
  final readResult = Completer<String?>();
  @override
  Future<String?> read(String key) => readResult.future;
}

class _DelayedTrustStore extends _Store {
  final started = Completer<void>();
  final finish = Completer<void>();
  bool failFirst = false;

  @override
  Future<void> write(String key, String value) async {
    if (key == 'mirquova.pairing.trusted_peers.v1' && !started.isCompleted) {
      started.complete();
      await finish.future;
      if (failFirst) throw StateError('Secure storage is unavailable.');
    }
    await super.write(key, value);
  }
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
  PairingSnapshot value = const PairingSnapshot();
  bool stopped = false;
  int hostStarts = 0;
  int joinStarts = 0;
  @override
  String startHost({
    required String localIpv4,
    required int port,
    required String hostAlias,
    required PairingIdentityMaterial identity,
  }) {
    hostStarts++;
    return 'payload';
  }

  @override
  bool startJoin({
    required Uint8List invitationPayload,
    required String confirmedFingerprintSha256,
    required String alias,
    required PairingIdentityMaterial identity,
  }) {
    joinStarts++;
    return true;
  }

  @override
  PairingSnapshot read() => value;
  @override
  bool approve() => true;
  @override
  bool reject() => true;
  @override
  void stop() => stopped = true;
}

void main() {
  for (final failFirst in [false, true]) {
    test(
      'new pairing saves while an earlier save is pending ($failFirst)',
      () async {
        final store = _DelayedTrustStore()..failFirst = failFirst;
        final transport = _Transport();
        final trust = PairingTrustRepository(store: store);
        final controller = PairingController(
          identities: PairingIdentityRepository(api: _Identity(), store: store),
          trustedPeers: trust,
          api: transport,
        );
        addTearDown(controller.dispose);
        await controller.startHosting(
          localIpv4: '192.168.1.20',
          hostAlias: 'Host',
        );
        transport.value = PairingSnapshot(
          status: PairingStatus.paired,
          peerAlias: 'First phone',
          peerCaCertificateDer: Uint8List.fromList([0x30, 0x01]),
        );
        controller.approve();
        await store.started.future;
        expect(controller.savingTrust, isTrue);

        transport.value = const PairingSnapshot(
          status: PairingStatus.waitingForPeer,
        );
        await controller.startHosting(
          localIpv4: '192.168.1.20',
          hostAlias: 'Host',
        );
        expect(controller.savingTrust, isFalse);
        transport.value = PairingSnapshot(
          status: PairingStatus.paired,
          peerAlias: 'Second phone',
          peerCaCertificateDer: Uint8List.fromList([0x30, 0x02]),
        );
        controller.approve();
        expect(controller.savingTrust, isTrue);

        store.finish.complete();
        final peers = await trust.list();
        await Future<void>.delayed(Duration.zero);
        expect(
          peers.map((peer) => peer.alias),
          failFirst ? ['Second phone'] : ['First phone', 'Second phone'],
        );
        expect(controller.savingTrust, isFalse);
        expect(controller.trustSaveFailed, isFalse);
        final writes = store.writes;
        controller.approve();
        await Future<void>.delayed(Duration.zero);
        expect((await trust.list()).length, peers.length);
        expect(store.writes, writes);
      },
    );
  }

  test(
    'invalid peer save reports failure instead of leaving saving active',
    () async {
      final store = _Store();
      final transport = _Transport()
        ..value = PairingSnapshot(
          status: PairingStatus.paired,
          peerAlias: '',
          peerCaCertificateDer: Uint8List.fromList([0x30, 0x01]),
        );
      final controller = PairingController(
        identities: PairingIdentityRepository(api: _Identity(), store: store),
        trustedPeers: PairingTrustRepository(store: store),
        api: transport,
      );
      addTearDown(controller.dispose);
      controller.approve();
      await Future<void>.delayed(Duration.zero);
      expect(controller.trustSaveFailed, isTrue);
      expect(controller.savingTrust, isFalse);
      expect(store.writes, 0);
    },
  );

  test('decodes native snake-case pairing statuses', () {
    expect(
      PairingSnapshot.fromJson({'status': 'waiting_for_peer'}).status,
      PairingStatus.waitingForPeer,
    );
    expect(
      PairingSnapshot.fromJson({'status': 'awaiting_approval'}).status,
      PairingStatus.awaitingApproval,
    );
  });

  test('stopping during identity load prevents a late host listener', () async {
    final store = _DelayedReadStore();
    final transport = _Transport();
    final controller = PairingController(
      identities: PairingIdentityRepository(api: _Identity(), store: store),
      trustedPeers: PairingTrustRepository(store: store),
      api: transport,
    );

    final start = controller.startHosting(
      localIpv4: '192.168.1.20',
      hostAlias: 'Host',
    );
    await Future<void>.delayed(Duration.zero);
    controller.stop();
    store.readResult.complete(null);

    await expectLater(start, throwsStateError);
    expect(transport.hostStarts, 0);
    controller.dispose();
  });

  test(
    'a superseded host request cannot clear the current request key',
    () async {
      final store = _DelayedReadStore();
      final transport = _Transport();
      final controller = PairingController(
        identities: PairingIdentityRepository(api: _Identity(), store: store),
        trustedPeers: PairingTrustRepository(store: store),
        api: transport,
      );

      final superseded = controller.startHosting(
        localIpv4: '192.168.1.20',
        hostAlias: 'Old host request',
      );
      await Future<void>.delayed(Duration.zero);
      final current = controller.startHosting(
        localIpv4: '192.168.1.20',
        hostAlias: 'Current host request',
      );
      await Future<void>.delayed(Duration.zero);
      store.readResult.complete(null);

      await expectLater(superseded, throwsStateError);
      expect(await current, 'payload');
      expect(transport.hostStarts, 1);
      controller.dispose();
    },
  );

  test('stopping during identity load prevents a late join attempt', () async {
    final store = _DelayedReadStore();
    final transport = _Transport();
    final controller = PairingController(
      identities: PairingIdentityRepository(api: _Identity(), store: store),
      trustedPeers: PairingTrustRepository(store: store),
      api: transport,
    );
    final invitation = PairingInvitation.parse(
      jsonEncode({
        'version': 2,
        'purpose': 'pairing',
        'endpoint': {'ipv4': '192.168.1.20', 'port': 45833},
        'identity_ca_certificate_der_hex': '3000',
        'secret': List<String>.filled(32, '11').join(),
        'ttl_seconds': 120,
      }),
    );

    final join = controller.join(
      invitation,
      alias: 'Phone',
      fingerprintConfirmed: true,
    );
    await Future<void>.delayed(Duration.zero);
    controller.stop();
    invitation.dispose();
    store.readResult.complete(null);

    await expectLater(join, throwsStateError);
    expect(transport.joinStarts, 0);
    controller.dispose();
  });

  test(
    'stopping clears the active invite without losing a completed pairing',
    () {
      final transport = _Transport();
      final store = _Store();
      final controller = PairingController(
        identities: PairingIdentityRepository(api: _Identity(), store: store),
        trustedPeers: PairingTrustRepository(store: store),
        api: transport,
      );

      controller.stop();
      expect(transport.stopped, isTrue);
      expect(controller.snapshot.status, PairingStatus.stopped);

      transport.value = const PairingSnapshot(status: PairingStatus.paired);
      controller.approve();
      controller.stop();
      expect(controller.snapshot.status, PairingStatus.paired);
      controller.dispose();
    },
  );

  test('a completed pairing persists its public peer certificate', () async {
    final transport = _Transport()
      ..value = PairingSnapshot(
        status: PairingStatus.paired,
        peerAlias: 'Phone',
        peerCaCertificateDer: Uint8List.fromList([0x30, 0x01]),
      );
    final store = _Store();
    final controller = PairingController(
      identities: PairingIdentityRepository(api: _Identity(), store: store),
      trustedPeers: PairingTrustRepository(store: store),
      api: transport,
    );

    controller.approve();
    await Future<void>.delayed(Duration.zero);
    final peers = await PairingTrustRepository(store: store).list();
    expect(peers.single.alias, 'Phone');
    expect(peers.single.fingerprintSha256, isNotEmpty);
    expect(
      jsonDecode(store.values['mirquova.pairing.trusted_peers.v1']!),
      isA<List>(),
    );
    expect(store.writes, 1);
    controller.approve();
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, 1);
    controller.dispose();
  });

  test('a failed trusted-peer save is visible and can be retried', () async {
    final transport = _Transport()
      ..value = PairingSnapshot(
        status: PairingStatus.paired,
        peerAlias: 'Phone',
        peerCaCertificateDer: Uint8List.fromList([0x30, 0x01]),
      );
    final store = _FailingWriteStore();
    final controller = PairingController(
      identities: PairingIdentityRepository(api: _Identity(), store: store),
      trustedPeers: PairingTrustRepository(store: store),
      api: transport,
    );

    controller.approve();
    await Future<void>.delayed(Duration.zero);
    expect(controller.trustSaveFailed, isTrue);
    expect(controller.savingTrust, isFalse);
    expect(await PairingTrustRepository(store: store).list(), isEmpty);

    store.failWrites = false;
    controller.retryTrustSave();
    await Future<void>.delayed(Duration.zero);
    expect(controller.trustSaveFailed, isFalse);
    expect(controller.savingTrust, isFalse);
    expect(
      (await PairingTrustRepository(store: store).list()).single.alias,
      'Phone',
    );
    expect(store.writes, 2);
    controller.dispose();
  });
}
