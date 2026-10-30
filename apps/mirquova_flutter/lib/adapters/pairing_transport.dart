import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

import '../core/discovery_port.dart';
import '../core/pairing_invitation.dart';
import 'pairing_identity.dart';

typedef _HostStart = Pointer<Utf8> Function(
  Pointer<Uint8>,
  Uint32,
  Uint16,
  Pointer<Uint8>,
  Uint32,
  Pointer<Uint8>,
  Uint32,
  Pointer<Uint8>,
  Uint32,
);
typedef _JoinStart = Int32 Function(
  Pointer<Uint8>,
  Uint32,
  Pointer<Uint8>,
  Pointer<Uint8>,
  Uint32,
  Pointer<Uint8>,
  Uint32,
  Pointer<Uint8>,
  Uint32,
);
typedef _SessionAction = Int32 Function();
typedef _Snapshot = Pointer<Utf8> Function();
typedef _Free = Void Function(Pointer<Utf8>);
typedef _Stop = Void Function();

enum PairingStatus {
  idle,
  waitingForPeer,
  connecting,
  awaitingApproval,
  paired,
  rejected,
  expired,
  stopped,
  error,
}

class PairingSnapshot {
  const PairingSnapshot({
    this.status = PairingStatus.idle,
    this.peerAlias,
    this.peerCaCertificateDer,
    this.errorCode,
  });

  final PairingStatus status;
  final String? peerAlias;
  final Uint8List? peerCaCertificateDer;
  final String? errorCode;
  bool get awaitingApproval => status == PairingStatus.awaitingApproval;

  factory PairingSnapshot.fromJson(Map<String, dynamic> json) {
    final statusName = (json['status'] as String).replaceAllMapped(
      RegExp(r'_([a-z])'),
      (match) => match[1]!.toUpperCase(),
    );
    final state = PairingStatus.values.byName(statusName);
    final encoded = json['peer_ca_certificate_der_hex'] as String?;
    final certificate = encoded == null ? null : _decodeHex(encoded);
    return PairingSnapshot(
      status: state,
      peerAlias: json['peer_alias'] as String?,
      peerCaCertificateDer: certificate,
      errorCode: json['error_code'] as String?,
    );
  }
}

abstract interface class PairingTransportApi {
  String startHost({
    required String localIpv4,
    required int port,
    required String hostAlias,
    required PairingIdentityMaterial identity,
  });
  bool startJoin({
    required Uint8List invitationPayload,
    required String confirmedFingerprintSha256,
    required String alias,
    required PairingIdentityMaterial identity,
  });
  PairingSnapshot read();
  bool approve();
  bool reject();
  void stop();
}

class FfiPairingTransportApi implements PairingTransportApi {
  FfiPairingTransportApi() {
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
    final abiVersion = library
        .lookupFunction<Uint32 Function(), int Function()>('mq_abi_version');
    if (abiVersion() != 2) {
      throw const FormatException('Unsupported native core ABI.');
    }
    _hostStart = library
        .lookupFunction<
          _HostStart,
          Pointer<Utf8> Function(
            Pointer<Uint8>,
            int,
            int,
            Pointer<Uint8>,
            int,
            Pointer<Uint8>,
            int,
            Pointer<Uint8>,
            int,
          )
        >('mq_pairing_host_start');
    _joinStart = library
        .lookupFunction<
          _JoinStart,
          int Function(
            Pointer<Uint8>,
            int,
            Pointer<Uint8>,
            Pointer<Uint8>,
            int,
            Pointer<Uint8>,
            int,
            Pointer<Uint8>,
            int,
          )
        >('mq_pairing_join');
    _approve = library.lookupFunction<_SessionAction, int Function()>(
      'mq_pairing_approve',
    );
    _reject = library.lookupFunction<_SessionAction, int Function()>(
      'mq_pairing_reject',
    );
    _snapshot = library.lookupFunction<_Snapshot, Pointer<Utf8> Function()>(
      'mq_pairing_snapshot',
    );
    _stop = library.lookupFunction<_Stop, void Function()>('mq_pairing_stop');
    _free = library.lookupFunction<_Free, void Function(Pointer<Utf8>)>(
      'mq_string_free',
    );
  }

  late final Pointer<Utf8> Function(
    Pointer<Uint8>,
    int,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
  )
  _hostStart;
  late final int Function(
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
  )
  _joinStart;
  late final int Function() _approve, _reject;
  late final Pointer<Utf8> Function() _snapshot;
  late final void Function() _stop;
  late final void Function(Pointer<Utf8>) _free;

  @override
  String startHost({
    required String localIpv4,
    required int port,
    required String hostAlias,
    required PairingIdentityMaterial identity,
  }) {
    final addressBytes = utf8.encode(localIpv4);
    final aliasBytes = utf8.encode(hostAlias);
    final address = _copyBytes(addressBytes);
    final alias = _copyBytes(aliasBytes);
    final certificate = _copyBytes(identity.certificateDer);
    final key = _copyBytes(identity.privateKeyPkcs8Der);
    try {
      final value = _hostStart(
        address,
        addressBytes.length,
        port,
        alias,
        aliasBytes.length,
        certificate,
        identity.certificateDer.length,
        key,
        identity.privateKeyPkcs8Der.length,
      );
      if (value == nullptr) {
        throw StateError('Could not start the pairing listener.');
      }
      try {
        return value.toDartString();
      } finally {
        _free(value);
      }
    } finally {
      _clearAndFree(key, identity.privateKeyPkcs8Der.length);
      calloc.free(certificate);
      calloc.free(alias);
      calloc.free(address);
    }
  }

  @override
  bool startJoin({
    required Uint8List invitationPayload,
    required String confirmedFingerprintSha256,
    required String alias,
    required PairingIdentityMaterial identity,
  }) {
    final payloadBytes = invitationPayload;
    final fingerprintBytes = _decodeHex(confirmedFingerprintSha256);
    final aliasBytes = utf8.encode(alias);
    if (fingerprintBytes.length != 32 ||
        payloadBytes.isEmpty ||
        payloadBytes.length > maxPairingInvitationBytes) {
      return false;
    }
    final payload = _copyBytes(payloadBytes);
    final fingerprint = _copyBytes(fingerprintBytes);
    final certificate = _copyBytes(identity.certificateDer);
    final key = _copyBytes(identity.privateKeyPkcs8Der);
    final aliasPointer = _copyBytes(aliasBytes);
    try {
      return _joinStart(
            payload,
            payloadBytes.length,
            fingerprint,
            certificate,
            identity.certificateDer.length,
            key,
            identity.privateKeyPkcs8Der.length,
            aliasPointer,
            aliasBytes.length,
          ) ==
          1;
    } finally {
      _clearAndFree(key, identity.privateKeyPkcs8Der.length);
      calloc.free(aliasPointer);
      calloc.free(certificate);
      calloc.free(fingerprint);
      _clearAndFree(payload, payloadBytes.length);
    }
  }

  @override
  PairingSnapshot read() {
    final value = _snapshot();
    if (value == nullptr) throw StateError('No native pairing snapshot.');
    try {
      return PairingSnapshot.fromJson(
        jsonDecode(value.toDartString()) as Map<String, dynamic>,
      );
    } finally {
      _free(value);
    }
  }

  @override
  bool approve() => _approve() == 1;
  @override
  bool reject() => _reject() == 1;
  @override
  void stop() => _stop();
}

class PairingController extends ChangeNotifier {
  PairingController({
    required this.identities,
    required this.trustedPeers,
    PairingTransportApi? api,
    this._privateIpv4AddressProvider,
  }) : _api = api ?? FfiPairingTransportApi();

  final PairingIdentityRepository identities;
  final PairingTrustRepository trustedPeers;
  final PairingTransportApi _api;
  final Future<List<String>> Function()? _privateIpv4AddressProvider;
  PairingSnapshot _snapshot = const PairingSnapshot();
  Timer? _poller;
  bool _disposed = false;
  int _operationGeneration = 0;
  int _trustSession = 0;
  String? _trustPersistedFingerprint;
  bool _savingTrust = false;
  bool _trustSaveFailed = false;

  PairingSnapshot get snapshot => _snapshot;
  bool get savingTrust => _savingTrust;
  bool get trustSaveFailed => _trustSaveFailed;
  bool get identityRecoveryRequired => identities.recoveryRequired;

  Future<void> resetCorruptIdentity() async {
    if (!identities.recoveryRequired) {
      throw StateError('There is no corrupt pairing identity to reset.');
    }
    _operationGeneration++;
    _poller?.cancel();
    _poller = null;
    _api.stop();
    await identities.resetCorruptIdentity();
    _snapshot = const PairingSnapshot();
    _trustPersistedFingerprint = null;
    notifyListeners();
  }

  void retryTrustSave() {
    _trustPersistedFingerprint = null;
    _persistTrustedPeerWhenPaired();
  }

  Future<String> startHosting({
    required String localIpv4,
    required String hostAlias,
    int port = 0,
  }) async {
    final generation = ++_operationGeneration;
    _ensureOperationCurrent(generation);
    final identity = await identities.loadOrCreate();
    try {
      _ensureOperationCurrent(generation);
      final payload = _api.startHost(
        localIpv4: localIpv4,
        port: port,
        hostAlias: hostAlias,
        identity: identity,
      );
      _beginPolling();
      _refresh();
      return payload;
    } finally {
      identity.clearPrivateKeyCopy();
    }
  }

  Future<void> join(
    PairingInvitation invitation, {
    required String alias,
    required bool fingerprintConfirmed,
  }) async {
    if (!fingerprintConfirmed) {
      throw StateError('Compare the fingerprint before starting pairing.');
    }
    final generation = ++_operationGeneration;
    _ensureOperationCurrent(generation);
    final fingerprint = invitation.fingerprintSha256;
    final identity = await identities.loadOrCreate();
    Uint8List? payload;
    try {
      _ensureOperationCurrent(generation);
      payload = invitation.takePayload();
      if (!_api.startJoin(
        invitationPayload: payload,
        confirmedFingerprintSha256: fingerprint,
        alias: alias,
        identity: identity,
      )) {
        throw StateError('Could not start the pairing attempt.');
      }
      _beginPolling();
      _refresh();
    } finally {
      payload?.fillRange(0, payload.length, 0);
      identity.clearPrivateKeyCopy();
    }
  }

  bool approve() {
    final result = _api.approve();
    _refresh();
    return result;
  }

  bool reject() {
    final result = _api.reject();
    _refresh();
    return result;
  }

  Future<List<String>> localPrivateIpv4Addresses() async {
    final provider = _privateIpv4AddressProvider;
    if (provider != null) return provider();
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final addresses = <String>{};
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (ManualEndpoint.parse(address.address, '1') != null) {
          addresses.add(address.address);
        }
      }
    }
    return addresses.toList()..sort();
  }

  void _beginPolling() {
    // A completed save belongs to the pairing that produced it. Repository
    // writes remain serialized even when a later session has already started.
    _trustSession++;
    _trustPersistedFingerprint = null;
    _savingTrust = false;
    _trustSaveFailed = false;
    _poller?.cancel();
    _poller = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _refresh(),
    );
  }

  void _refresh() {
    if (_disposed) return;
    try {
      _snapshot = _api.read();
      _persistTrustedPeerWhenPaired();
      if (switch (_snapshot.status) {
        PairingStatus.paired ||
        PairingStatus.rejected ||
        PairingStatus.expired ||
        PairingStatus.stopped ||
        PairingStatus.error => true,
        _ => false,
      }) {
        _poller?.cancel();
        _poller = null;
        if (_snapshot.status == PairingStatus.paired) _api.stop();
      }
    } on Exception {
      _snapshot = const PairingSnapshot(
        status: PairingStatus.error,
        errorCode: 'native_core_unavailable',
      );
      _poller?.cancel();
      _poller = null;
    }
    notifyListeners();
  }

  void _persistTrustedPeerWhenPaired() {
    final certificate = _snapshot.peerCaCertificateDer;
    if (_snapshot.status != PairingStatus.paired ||
        certificate == null ||
        _savingTrust ||
        _trustPersistedFingerprint == _fingerprint(certificate)) {
      return;
    }
    _savingTrust = true;
    _trustSaveFailed = false;
    final alias = _snapshot.peerAlias ?? 'Mirquova device';
    unawaited(_saveTrustedPeer(_trustSession, alias, certificate));
  }

  Future<void> _saveTrustedPeer(
    int session,
    String alias,
    Uint8List certificate,
  ) async {
    try {
      await trustedPeers.trust(alias: alias, certificateDer: certificate);
      if (session == _trustSession) {
        _trustPersistedFingerprint = _fingerprint(certificate);
      }
    } on Object {
      if (session == _trustSession) _trustSaveFailed = true;
    } finally {
      if (session == _trustSession) {
        _savingTrust = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  void stop() {
    _operationGeneration++;
    _poller?.cancel();
    _poller = null;
    _api.stop();
    if (_snapshot.status != PairingStatus.paired) {
      _snapshot = const PairingSnapshot(status: PairingStatus.stopped);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _operationGeneration++;
    _poller?.cancel();
    _api.stop();
    super.dispose();
  }

  void _ensureOperationCurrent(int generation) {
    if (_disposed || generation != _operationGeneration) {
      throw StateError('Pairing was cancelled.');
    }
  }
}

String _fingerprint(List<int> certificate) =>
    sha256.convert(certificate).toString();

Pointer<Uint8> _copyBytes(List<int> bytes) {
  final pointer = calloc<Uint8>(bytes.length);
  pointer.asTypedList(bytes.length).setAll(0, bytes);
  return pointer;
}

void _clearAndFree(Pointer<Uint8> pointer, int length) {
  pointer.asTypedList(length).fillRange(0, length, 0);
  calloc.free(pointer);
}

Uint8List _decodeHex(String value) {
  if (value.isEmpty ||
      value.length.isOdd ||
      !RegExp(r'^[0-9a-f]+$').hasMatch(value)) {
    throw const FormatException('Pairing fingerprint is invalid.');
  }
  final bytes = Uint8List(value.length ~/ 2);
  for (var index = 0; index < value.length; index += 2) {
    bytes[index ~/ 2] = int.parse(value.substring(index, index + 2), radix: 16);
  }
  return bytes;
}
