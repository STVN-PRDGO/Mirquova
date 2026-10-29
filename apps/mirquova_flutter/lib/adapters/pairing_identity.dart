import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

typedef _CreateNativeIdentity = Pointer<_NativePairingIdentity> Function();
typedef _FreeNativeIdentity = Void Function(Pointer<_NativePairingIdentity>);
typedef _ValidateIdentity = Int32 Function(
  Pointer<Uint8>,
  Uint32,
  Pointer<Uint8>,
  Uint32,
);

final class _NativePairingIdentity extends Struct {
  external Pointer<Uint8> certificateDer;
  @Uint32()
  external int certificateLength;
  external Pointer<Uint8> privateKeyPkcs8Der;
  @Uint32()
  external int privateKeyLength;
}

abstract interface class PairingIdentityApi {
  PairingIdentityMaterial create();
  bool validate(PairingIdentityMaterial identity);
}

class PairingIdentityMaterial {
  PairingIdentityMaterial({
    required List<int> certificateDer,
    required List<int> privateKeyPkcs8Der,
  }) : certificateDer = Uint8List.fromList(certificateDer),
       privateKeyPkcs8Der = Uint8List.fromList(privateKeyPkcs8Der);

  final Uint8List certificateDer;
  final Uint8List privateKeyPkcs8Der;

  void clearPrivateKeyCopy() =>
      privateKeyPkcs8Der.fillRange(0, privateKeyPkcs8Der.length, 0);

  @override
  String toString() => 'PairingIdentityMaterial { redacted }';
}

class FfiPairingIdentityApi implements PairingIdentityApi {
  FfiPairingIdentityApi() {
    const override = String.fromEnvironment('MIRQUOVA_CORE_LIBRARY');
    final path = override.isNotEmpty
        ? override
        : Platform.isWindows
        ? '${File(Platform.resolvedExecutable).parent.path}/mirquova_core.dll'
        : Platform.isMacOS
        ? '${File(Platform.resolvedExecutable).parent.parent.path}/Frameworks/libmirquova_core.dylib'
        : Platform.isLinux
        ? '${File(Platform.resolvedExecutable).parent.path}/lib/libmirquova_core.so'
        : 'libmirquova_core.so';
    final library = Platform.isIOS && override.isEmpty
        ? DynamicLibrary.process()
        : DynamicLibrary.open(path);
    if (library.lookupFunction<Uint32 Function(), int Function()>(
          'mq_abi_version',
        )() !=
        2) {
      throw const FormatException('Unsupported native core ABI.');
    }
    _create = library
        .lookupFunction<
          _CreateNativeIdentity,
          Pointer<_NativePairingIdentity> Function()
        >('mq_pairing_identity_create');
    _freeIdentity = library
        .lookupFunction<
          _FreeNativeIdentity,
          void Function(Pointer<_NativePairingIdentity>)
        >('mq_pairing_identity_free');
    _validate = library
        .lookupFunction<
          _ValidateIdentity,
          int Function(Pointer<Uint8>, int, Pointer<Uint8>, int)
        >('mq_pairing_identity_validate');
  }

  late final Pointer<_NativePairingIdentity> Function() _create;
  late final void Function(Pointer<_NativePairingIdentity>) _freeIdentity;
  late final int Function(Pointer<Uint8>, int, Pointer<Uint8>, int) _validate;

  @override
  PairingIdentityMaterial create() {
    final pointer = _create();
    if (pointer == nullptr) {
      throw StateError('Could not create a device identity.');
    }
    try {
      final value = pointer.ref;
      if (value.certificateDer == nullptr ||
          value.privateKeyPkcs8Der == nullptr ||
          value.certificateLength == 0 ||
          value.certificateLength > 512 ||
          value.privateKeyLength == 0 ||
          value.privateKeyLength > 4096) {
        throw const FormatException('Native identity response is invalid.');
      }
      return PairingIdentityMaterial(
        certificateDer: value.certificateDer.asTypedList(
          value.certificateLength,
        ),
        privateKeyPkcs8Der: value.privateKeyPkcs8Der.asTypedList(
          value.privateKeyLength,
        ),
      );
    } finally {
      _freeIdentity(pointer);
    }
  }

  @override
  bool validate(PairingIdentityMaterial identity) {
    if (identity.certificateDer.isEmpty ||
        identity.certificateDer.length > 512 ||
        identity.privateKeyPkcs8Der.isEmpty ||
        identity.privateKeyPkcs8Der.length > 4096) {
      return false;
    }
    final certificate = calloc<Uint8>(identity.certificateDer.length);
    final key = calloc<Uint8>(identity.privateKeyPkcs8Der.length);
    try {
      certificate
          .asTypedList(identity.certificateDer.length)
          .setAll(0, identity.certificateDer);
      key
          .asTypedList(identity.privateKeyPkcs8Der.length)
          .setAll(0, identity.privateKeyPkcs8Der);
      return _validate(
            certificate,
            identity.certificateDer.length,
            key,
            identity.privateKeyPkcs8Der.length,
          ) ==
          1;
    } finally {
      key
          .asTypedList(identity.privateKeyPkcs8Der.length)
          .fillRange(0, identity.privateKeyPkcs8Der.length, 0);
      calloc.free(key);
      calloc.free(certificate);
    }
  }
}

abstract interface class PairingSecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterPairingSecretStore implements PairingSecretStore {
  FlutterPairingSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? storageForPlatform(isMacOS: Platform.isMacOS);

  @visibleForTesting
  static FlutterSecureStorage storageForPlatform({required bool isMacOS}) {
    if (isMacOS) {
      // The data-protection Keychain requires a provisioned Keychain Sharing
      // entitlement. This ad-hoc preview does not share secrets with another
      // app, so use the plugin's legacy Keychain mode on macOS.
      return const FlutterSecureStorage(
        mOptions: MacOsOptions(usesDataProtectionKeychain: false),
      );
    }
    return const FlutterSecureStorage();
  }

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class TrustedPeer {
  const TrustedPeer({
    required this.fingerprintSha256,
    required this.alias,
    required this.certificateDer,
    required this.pairedAt,
  });

  final String fingerprintSha256;
  final String alias;
  final String certificateDer;
  final DateTime pairedAt;
}

class PairingTrustRepository {
  PairingTrustRepository({required this.store, this.storageKey = _storageKey});
  static const _storageKey = 'mirquova.pairing.trusted_peers.v1';
  final PairingSecretStore store;
  final String storageKey;
  Future<void> _mutationTail = Future<void>.value();

  Future<List<TrustedPeer>> list() async {
    await _mutationTail;
    return _readCurrent();
  }

  Future<List<TrustedPeer>> _readCurrent() async {
    final value = await store.read(storageKey);
    if (value == null) return const [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) throw const FormatException();
      return decoded
          .map((item) {
            if (item is! Map<String, dynamic> ||
                item.length != 4 ||
                item['fingerprint'] is! String ||
                item['alias'] is! String ||
                item['certificate'] is! String ||
                item['paired_at'] is! String) {
              throw const FormatException();
            }
            final peer = TrustedPeer(
              fingerprintSha256: item['fingerprint'] as String,
              alias: item['alias'] as String,
              certificateDer: item['certificate'] as String,
              pairedAt: DateTime.parse(item['paired_at'] as String),
            );
            if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(peer.fingerprintSha256) ||
                peer.alias.isEmpty ||
                peer.certificateDer.isEmpty ||
                peer.certificateDer.length > 1024) {
              throw const FormatException();
            }
            final certificate = base64Decode(peer.certificateDer);
            if (sha256.convert(certificate).toString() !=
                peer.fingerprintSha256) {
              throw const FormatException();
            }
            return peer;
          })
          .toList(growable: false);
    } on Exception {
      throw StateError('The saved trusted-device list is corrupt.');
    }
  }

  Future<void> trust({
    required String alias,
    required List<int> certificateDer,
    DateTime? pairedAt,
  }) {
    if (alias.isEmpty ||
        alias.length > 64 ||
        certificateDer.isEmpty ||
        certificateDer.length > 512) {
      throw const FormatException('Trusted peer identity is invalid.');
    }
    final encodedCertificate = base64Encode(certificateDer);
    final fingerprint = sha256.convert(certificateDer).toString();
    return _mutate(() async {
      final peers = await _readCurrent();
      final updated = [
        for (final peer in peers)
          if (peer.fingerprintSha256 != fingerprint) peer,
        TrustedPeer(
          fingerprintSha256: fingerprint,
          alias: alias,
          certificateDer: encodedCertificate,
          pairedAt: pairedAt ?? DateTime.now().toUtc(),
        ),
      ];
      await store.write(storageKey, _encodePeers(updated));
    });
  }

  Future<void> revoke(String fingerprintSha256) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprintSha256)) {
      throw const FormatException('Trusted peer fingerprint is invalid.');
    }
    return _mutate(() async {
      final peers = await _readCurrent();
      final remaining = peers.where(
        (peer) => peer.fingerprintSha256 != fingerprintSha256,
      );
      if (remaining.length == peers.length) return;
      if (remaining.isEmpty) {
        await store.delete(storageKey);
        return;
      }
      await store.write(storageKey, _encodePeers(remaining));
    });
  }

  Future<void> _mutate(Future<void> Function() action) {
    final operation = _mutationTail.then((_) => action());
    _mutationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  String _encodePeers(Iterable<TrustedPeer> peers) => jsonEncode([
    for (final peer in peers)
      {
        'fingerprint': peer.fingerprintSha256,
        'alias': peer.alias,
        'certificate': peer.certificateDer,
        'paired_at': peer.pairedAt.toUtc().toIso8601String(),
      },
  ]);
}

class PairingIdentityRepository {
  PairingIdentityRepository({
    required this.api,
    required this.store,
    this.storageKey = _storageKey,
  });

  static const _storageKey = 'mirquova.pairing.identity.v1';
  final PairingIdentityApi api;
  final PairingSecretStore store;
  final String storageKey;
  Future<PairingIdentityMaterial>? _loading;
  int _loadingWaiters = 0;
  bool _recoveryRequired = false;

  bool get recoveryRequired => _recoveryRequired;

  /// Removes a corrupt saved identity only after an explicit user decision.
  /// The next pairing attempt creates a new identity; existing peers may need
  /// to pair with this installation again.
  Future<void> resetCorruptIdentity() async {
    if (!_recoveryRequired || _loading != null) {
      throw StateError('There is no corrupt pairing identity to reset.');
    }
    await store.delete(storageKey);
    _recoveryRequired = false;
  }

  Future<PairingIdentityMaterial> loadOrCreate() {
    final future = _loading ??= _loadOrCreate();
    _loadingWaiters++;
    return _copyAndRelease(future);
  }

  Future<PairingIdentityMaterial> _copyAndRelease(
    Future<PairingIdentityMaterial> future,
  ) async {
    PairingIdentityMaterial? source;
    try {
      source = await future;
      return PairingIdentityMaterial(
        certificateDer: source.certificateDer,
        privateKeyPkcs8Der: source.privateKeyPkcs8Der,
      );
    } finally {
      _loadingWaiters--;
      if (_loadingWaiters == 0 && identical(_loading, future)) {
        source?.clearPrivateKeyCopy();
        _loading = null;
      }
    }
  }

  Future<PairingIdentityMaterial> _loadOrCreate() async {
    final stored = await store.read(storageKey);
    _recoveryRequired = false;
    if (stored != null) {
      PairingIdentityMaterial? identity;
      var retained = false;
      try {
        final value = jsonDecode(stored);
        if (value is! Map<String, dynamic> ||
            value.length != 3 ||
            value['version'] != 1 ||
            value['certificate'] is! String ||
            value['private_key'] is! String) {
          throw const FormatException();
        }
        identity = PairingIdentityMaterial(
          certificateDer: base64Decode(value['certificate'] as String),
          privateKeyPkcs8Der: base64Decode(value['private_key'] as String),
        );
        if (!api.validate(identity)) {
          throw const FormatException();
        }
        retained = true;
        return identity;
      } on Exception {
        _recoveryRequired = true;
        throw StateError(
          'The saved pairing identity is unavailable or corrupt. Pairing is disabled; reset identity only through an explicit recovery action.',
        );
      } finally {
        if (!retained) identity?.clearPrivateKeyCopy();
      }
    }

    final identity = api.create();
    var retained = false;
    try {
      if (!api.validate(identity)) {
        throw StateError(
          'The native core returned an invalid device identity.',
        );
      }
      final encoded = jsonEncode({
        'version': 1,
        'certificate': base64Encode(identity.certificateDer),
        'private_key': base64Encode(identity.privateKeyPkcs8Der),
      });
      await store.write(storageKey, encoded);
      retained = true;
      return identity;
    } finally {
      if (!retained) identity.clearPrivateKeyCopy();
    }
  }
}
