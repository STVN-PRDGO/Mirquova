import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../core/discovery_port.dart';
import '../core/transfer_state.dart';
import 'pairing_identity.dart';

typedef _StartNative = Int32 Function(
  Pointer<Uint8>,
  Uint32,
  Pointer<Uint8>,
  Uint32,
  Pointer<Uint8>,
  Uint32,
);
typedef _Start = int Function(
  Pointer<Uint8>,
  int,
  Pointer<Uint8>,
  int,
  Pointer<Uint8>,
  int,
);
typedef _ActionNative = Int32 Function();
typedef _Action = int Function();
typedef _SnapshotNative = Pointer<Utf8> Function();
typedef _Snapshot = Pointer<Utf8> Function();
typedef _StopNative = Void Function();
typedef _Stop = void Function();
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _Free = void Function(Pointer<Utf8>);

class NativeTransferApi {
  NativeTransferApi() {
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
    _receive = library.lookupFunction<_StartNative, _Start>(
      'mq_transfer_receive_start',
    );
    _send = library.lookupFunction<_StartNative, _Start>(
      'mq_transfer_send_start',
    );
    _approve = library.lookupFunction<_ActionNative, _Action>(
      'mq_transfer_approve',
    );
    _reject = library.lookupFunction<_ActionNative, _Action>(
      'mq_transfer_reject',
    );
    _snapshot = library.lookupFunction<_SnapshotNative, _Snapshot>(
      'mq_transfer_snapshot',
    );
    _stop = library.lookupFunction<_StopNative, _Stop>('mq_transfer_stop');
    _free = library.lookupFunction<_FreeNative, _Free>('mq_string_free');
  }

  late final _Start _receive;
  late final _Start _send;
  late final _Action _approve;
  late final _Action _reject;
  late final _Snapshot _snapshot;
  late final _Stop _stop;
  late final _Free _free;

  bool startReceive({
    required String configJson,
    required PairingIdentityMaterial identity,
  }) => _start(_receive, configJson, identity);

  bool startSend({
    required String configJson,
    required PairingIdentityMaterial identity,
  }) => _start(_send, configJson, identity);

  bool _start(
    _Start function,
    String configJson,
    PairingIdentityMaterial identity,
  ) {
    final configBytes = utf8.encode(configJson);
    final config = _copy(configBytes);
    final certificate = _copy(identity.certificateDer);
    final key = _copy(identity.privateKeyPkcs8Der);
    try {
      return function(
            config,
            configBytes.length,
            certificate,
            identity.certificateDer.length,
            key,
            identity.privateKeyPkcs8Der.length,
          ) ==
          1;
    } finally {
      calloc.free(config);
      calloc.free(certificate);
      _clear(key, identity.privateKeyPkcs8Der.length);
    }
  }

  TransferSnapshot read() {
    final value = _snapshot();
    if (value == nullptr) {
      throw StateError('No native transfer snapshot.');
    }
    try {
      return TransferSnapshot.fromJson(
        jsonDecode(value.toDartString()) as Map<String, dynamic>,
      );
    } finally {
      _free(value);
    }
  }

  bool approve() => _approve() == 1;
  bool reject() => _reject() == 1;
  void stop() => _stop();
}

class TransferController extends ChangeNotifier {
  TransferController({
    required this.identities,
    required this.trustedPeers,
    NativeTransferApi? api,
  }) : _api = api ?? NativeTransferApi();

  final PairingIdentityRepository identities;
  final PairingTrustRepository trustedPeers;
  final NativeTransferApi _api;
  TransferSnapshot snapshot = const TransferSnapshot();
  String? message;
  Timer? _poller;
  bool _disposed = false;

  Future<List<String>> localPrivateIpv4Addresses() async {
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

  Future<void> receive({
    required String localIpv4,
    required String destination,
  }) async {
    final peers = await trustedPeers.list();
    if (peers.isEmpty) {
      _setMessage('Pair a device before receiving files.');
      return;
    }
    if (ManualEndpoint.parse(localIpv4, '1') == null) {
      _setMessage('Choose a private IPv4 address on this LAN.');
      return;
    }
    final identity = await identities.loadOrCreate();
    final config = jsonEncode({
      'local_ipv4': localIpv4,
      'port': 0,
      'destination_directory': destination,
      'peer_ca_certificates_der_hex': [
        for (final peer in peers) _hex(base64Decode(peer.certificateDer)),
      ],
    });
    final started = _api.startReceive(configJson: config, identity: identity);
    identity.clearPrivateKeyCopy();
    if (!started) {
      _setMessage(
        'Receiving could not start. Check the folder and the paired device.',
      );
      return;
    }
    _listen();
  }

  Future<void> send({
    required TrustedPeer peer,
    required String host,
    required int port,
    required List<String> paths,
  }) async {
    if (ManualEndpoint.parse(host, '$port') == null || paths.isEmpty) {
      _setMessage(
        'Choose a private LAN address, a port, and at least one file.',
      );
      return;
    }
    final identity = await identities.loadOrCreate();
    final config = jsonEncode({
      'peer_ipv4': host,
      'port': port,
      'peer_ca_certificate_der_hex': _hex(base64Decode(peer.certificateDer)),
      'paths': paths,
    });
    final started = _api.startSend(configJson: config, identity: identity);
    identity.clearPrivateKeyCopy();
    if (!started) {
      _setMessage(
        'Sending could not start. The file or paired device was rejected.',
      );
      return;
    }
    _listen();
  }

  bool approve() {
    final accepted = _api.approve();
    _refresh();
    return accepted;
  }

  bool reject() {
    final declined = _api.reject();
    _refresh();
    return declined;
  }

  void stop() {
    _poller?.cancel();
    _api.stop();
    snapshot = const TransferSnapshot(status: TransferStatus.stopped);
    message = transferStatusMessage(snapshot);
    if (!_disposed) notifyListeners();
  }

  void _listen() {
    _poller?.cancel();
    _refresh();
    _poller = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _refresh();
      if (snapshot.finished) _poller?.cancel();
    });
  }

  void _refresh() {
    try {
      snapshot = _api.read();
      message = transferStatusMessage(snapshot);
    } on Object {
      snapshot = const TransferSnapshot(status: TransferStatus.error);
      message = 'The transfer status could not be read.';
      _poller?.cancel();
    }
    if (!_disposed) notifyListeners();
  }

  void _setMessage(String value) {
    message = value;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poller?.cancel();
    _api.stop();
    super.dispose();
  }
}

Pointer<Uint8> _copy(List<int> bytes) {
  final pointer = calloc<Uint8>(bytes.length);
  pointer.asTypedList(bytes.length).setAll(0, bytes);
  return pointer;
}

void _clear(Pointer<Uint8> pointer, int length) {
  pointer.asTypedList(length).fillRange(0, length, 0);
  calloc.free(pointer);
}

String _hex(List<int> bytes) =>
    [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();
