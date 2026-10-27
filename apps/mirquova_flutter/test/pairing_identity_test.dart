import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/adapters/pairing_identity.dart';

class _MemorySecretStore implements PairingSecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _PausedWriteSecretStore extends _MemorySecretStore {
  final writeStarted = Completer<void>();
  final finishWrite = Completer<void>();

  @override
  Future<void> write(String key, String value) async {
    if (!writeStarted.isCompleted) {
      writeStarted.complete();
      await finishWrite.future;
    }
    await super.write(key, value);
  }
}

class _FakeIdentityApi implements PairingIdentityApi {
  int createCount = 0;
  bool valid = true;
  bool throwOnValidate = false;
  late PairingIdentityMaterial created;
  PairingIdentityMaterial? lastValidated;

  @override
  PairingIdentityMaterial create() {
    createCount++;
    created = PairingIdentityMaterial(
      certificateDer: [0x30, 0x01],
      privateKeyPkcs8Der: [0x01, 0x02, 0x03],
    );
    return created;
  }

  @override
  bool validate(PairingIdentityMaterial identity) {
    lastValidated = identity;
    if (throwOnValidate) throw StateError('simulated native validation error');
    return valid;
  }
}

void main() {
  test(
    'creates once and stores identity material as one protected record',
    () async {
      final api = _FakeIdentityApi();
      final store = _MemorySecretStore();
      final repository = PairingIdentityRepository(api: api, store: store);

      final first = repository.loadOrCreate();
      final second = repository.loadOrCreate();
      final identities = await Future.wait([first, second]);

      expect(api.createCount, 1);
      expect(identities[0].certificateDer, [0x30, 0x01]);
      expect(identities[1].privateKeyPkcs8Der, [1, 2, 3]);
      expect(identical(identities[0], identities[1]), isFalse);
      identities[0].clearPrivateKeyCopy();
      expect(identities[1].privateKeyPkcs8Der, [1, 2, 3]);
      expect(store.values, hasLength(1));
      final stored =
          jsonDecode(store.values.values.single) as Map<String, dynamic>;
      expect(stored['version'], 1);
      expect(base64Decode(stored['certificate']), [0x30, 0x01]);
      expect(base64Decode(stored['private_key']), [1, 2, 3]);
      expect(first.toString(), isNot(contains('private_key')));
    },
  );

  test('loads and validates the saved identity without replacing it', () async {
    final api = _FakeIdentityApi();
    final store = _MemorySecretStore()
      ..values['mirquova.pairing.identity.v1'] = jsonEncode({
        'version': 1,
        'certificate': base64Encode([0x30, 0x01]),
        'private_key': base64Encode([1, 2, 3]),
      });
    final identity = await PairingIdentityRepository(
      api: api,
      store: store,
    ).loadOrCreate();

    expect(identity.certificateDer, [0x30, 0x01]);
    expect(api.createCount, 0);
  });

  test(
    'temporary storage keys isolate pairing probes from normal app state',
    () async {
      final api = _FakeIdentityApi();
      final store = _MemorySecretStore()
        ..values['mirquova.pairing.identity.v1'] = 'preserved identity'
        ..values['mirquova.pairing.trusted_peers.v1'] = 'preserved peers';
      final identity = await PairingIdentityRepository(
        api: api,
        store: store,
        storageKey: 'mirquova.pairing.integration.identity.v1',
      ).loadOrCreate();
      identity.clearPrivateKeyCopy();

      final trust = PairingTrustRepository(
        store: store,
        storageKey: 'mirquova.pairing.integration.peers.v1',
      );
      await trust.trust(
        alias: 'Test probe',
        certificateDer: [0x30, 0x03, 0x02, 0x01, 0x01],
      );
      final peer = (await trust.list()).single;
      await trust.revoke(peer.fingerprintSha256);
      await store.delete('mirquova.pairing.integration.identity.v1');

      expect(
        store.values['mirquova.pairing.identity.v1'],
        'preserved identity',
      );
      expect(
        store.values['mirquova.pairing.trusted_peers.v1'],
        'preserved peers',
      );
      expect(
        store.values.keys,
        isNot(contains('mirquova.pairing.integration.identity.v1')),
      );
      expect(
        store.values.keys,
        isNot(contains('mirquova.pairing.integration.peers.v1')),
      );
    },
  );

  test(
    'fails closed on corrupt storage and does not silently replace identity',
    () async {
      final api = _FakeIdentityApi();
      final store = _MemorySecretStore()
        ..values['mirquova.pairing.identity.v1'] = '{broken';
      final repository = PairingIdentityRepository(api: api, store: store);

      await expectLater(repository.loadOrCreate(), throwsStateError);
      expect(api.createCount, 0);
      expect(store.values['mirquova.pairing.identity.v1'], '{broken');
    },
  );

  test(
    'does not persist an identity rejected by the native validator',
    () async {
      final api = _FakeIdentityApi()..valid = false;
      final store = _MemorySecretStore();
      final repository = PairingIdentityRepository(api: api, store: store);

      await expectLater(repository.loadOrCreate(), throwsStateError);
      expect(store.values, isEmpty);
      expect(api.created.privateKeyPkcs8Der, [0, 0, 0]);
    },
  );

  test('clears a created key when native identity validation throws', () async {
    final api = _FakeIdentityApi()..throwOnValidate = true;
    final store = _MemorySecretStore();

    await expectLater(
      PairingIdentityRepository(api: api, store: store).loadOrCreate(),
      throwsStateError,
    );

    expect(api.created.privateKeyPkcs8Der, [0, 0, 0]);
    expect(store.values, isEmpty);
  });

  test('clears a loaded key when native identity validation throws', () async {
    final api = _FakeIdentityApi()..throwOnValidate = true;
    final store = _MemorySecretStore()
      ..values['mirquova.pairing.identity.v1'] = jsonEncode({
        'version': 1,
        'certificate': base64Encode([0x30, 0x01]),
        'private_key': base64Encode([1, 2, 3]),
      });

    await expectLater(
      PairingIdentityRepository(api: api, store: store).loadOrCreate(),
      throwsStateError,
    );

    expect(api.lastValidated!.privateKeyPkcs8Der, [0, 0, 0]);
  });

  test(
    'trusted peers persist by certificate fingerprint and can be revoked',
    () async {
      final store = _MemorySecretStore();
      final repository = PairingTrustRepository(store: store);
      final certificate = [0x30, 0x03, 0x02, 0x01, 0x01];
      await repository.trust(alias: 'Phone', certificateDer: certificate);
      await repository.trust(
        alias: 'Updated phone name',
        certificateDer: certificate,
      );

      final peers = await repository.list();
      expect(peers, hasLength(1));
      expect(peers.single.alias, 'Updated phone name');
      expect(base64Decode(peers.single.certificateDer), certificate);
      await repository.revoke(peers.single.fingerprintSha256);
      expect(await repository.list(), isEmpty);
      expect(store.values, isEmpty);
    },
  );

  test('a queued revoke wins over an in-flight trust write', () async {
    final store = _PausedWriteSecretStore();
    final repository = PairingTrustRepository(store: store);
    final certificate = [0x30, 0x03, 0x02, 0x01, 0x01];
    final fingerprint = sha256.convert(certificate).toString();

    final pairingWrite = repository.trust(
      alias: 'Phone',
      certificateDer: certificate,
    );
    await store.writeStarted.future;
    final revoke = repository.revoke(fingerprint);
    store.finishWrite.complete();
    await Future.wait([pairingWrite, revoke]);

    expect(await repository.list(), isEmpty);
    expect(store.values, isEmpty);
  });

  test('corrupt trusted-peer fingerprints fail closed', () async {
    final store = _MemorySecretStore()
      ..values['mirquova.pairing.trusted_peers.v1'] = jsonEncode([
        {
          'fingerprint': List.filled(64, '0').join(),
          'alias': 'Phone',
          'certificate': base64Encode([0x30, 0x00]),
          'paired_at': DateTime.utc(2026).toIso8601String(),
        },
      ]);
    await expectLater(
      PairingTrustRepository(store: store).list(),
      throwsStateError,
    );
  });
}
