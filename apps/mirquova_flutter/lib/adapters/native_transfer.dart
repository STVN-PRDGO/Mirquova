import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

abstract interface class TransferApi {
  bool startReceive({
    required String configJson,
    required PairingIdentityMaterial identity,
  });
  bool startSend({
    required String configJson,
    required PairingIdentityMaterial identity,
  });
  TransferSnapshot readReceive();
  TransferSnapshot readSend();
  bool approve();
  bool reject();
  void stopReceive();
  void stopSend();
}

class NativeTransferApi implements TransferApi {
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
    _receiveSnapshot = library.lookupFunction<_SnapshotNative, _Snapshot>(
      'mq_transfer_receive_snapshot',
    );
    _sendSnapshot = library.lookupFunction<_SnapshotNative, _Snapshot>(
      'mq_transfer_send_snapshot',
    );
    _receiveStop = library.lookupFunction<_StopNative, _Stop>(
      'mq_transfer_receive_stop',
    );
    _sendStop = library.lookupFunction<_StopNative, _Stop>(
      'mq_transfer_send_stop',
    );
    _free = library.lookupFunction<_FreeNative, _Free>('mq_string_free');
  }

  late final _Start _receive;
  late final _Start _send;
  late final _Action _approve;
  late final _Action _reject;
  late final _Snapshot _receiveSnapshot;
  late final _Snapshot _sendSnapshot;
  late final _Stop _receiveStop;
  late final _Stop _sendStop;
  late final _Free _free;

  @override
  bool startReceive({
    required String configJson,
    required PairingIdentityMaterial identity,
  }) => _start(_receive, configJson, identity);

  @override
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

  @override
  TransferSnapshot readReceive() => _read(_receiveSnapshot);

  @override
  TransferSnapshot readSend() => _read(_sendSnapshot);

  TransferSnapshot _read(_Snapshot read) {
    final value = read();
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

  @override
  bool approve() => _approve() == 1;
  @override
  bool reject() => _reject() == 1;
  @override
  void stopReceive() => _receiveStop();
  @override
  void stopSend() => _sendStop();
}

/// The name other devices see. Android reports "localhost" as its hostname,
/// so it asks the system for the phone's own name instead.
Future<String> localDeviceName() async {
  if (Platform.isAndroid) {
    try {
      final name = await const MethodChannel('dev.mirquova/app')
          .invokeMethod<String>('getDeviceName');
      if (name != null && PresenceState.validAlias(name)) return name.trim();
    } on Object {
      // Fall back to the hostname below.
    }
  }
  return Platform.localHostname;
}

/// Copies received files into the system Downloads folder when the native
/// inbox is app-private storage. The native session never writes there.
Future<String> publishReceivedFiles({
  required String destination,
  required List<String> names,
}) async {
  if (!Platform.isAndroid || names.isEmpty) return destination;
  try {
    final published = await const MethodChannel('dev.mirquova/app')
        .invokeMethod<String>('publishReceivedFiles', {
          'directory': destination,
          'names': names,
        });
    if (published != null && published.isNotEmpty) return published;
  } on Object {
    // The app inbox still has the verified files.
  }
  return destination;
}

/// Where received files go when the user has not picked a folder.
Future<String?> defaultReceiveFolder() async {
  if (Platform.isAndroid) {
    try {
      return await const MethodChannel('dev.mirquova/app')
          .invokeMethod<String>('getReceiveDirectory');
    } on Object {
      return null;
    }
  }
  final home = Platform.isWindows
      ? Platform.environment['USERPROFILE']
      : Platform.environment['HOME'];
  if (home == null || home.isEmpty) return null;
  final separator = Platform.pathSeparator;
  return '$home${separator}Downloads${separator}Mirquova';
}

/// Outcome of one incoming offer, for a short confirmation after it ends.
class IncomingResult {
  const IncomingResult({
    required this.snapshot,
    required this.senderAlias,
    required this.folder,
  });
  final TransferSnapshot snapshot;
  final String senderAlias;
  final String folder;
}

/// Keeps this device ready to receive from paired devices while the app is
/// open, and sends to one paired device at a time. Every incoming offer still
/// waits for the person on this device to accept it.
class TransferService extends ChangeNotifier {
  TransferService({
    required this.identities,
    required this.trustedPeers,
    required this.settings,
    TransferApi? api,
    this.discovery,
    String? alias,
    Future<String?> Function()? defaultFolder,
    this.receivePoll = const Duration(milliseconds: 300),
    this.retryDelay = const Duration(seconds: 5),
    this.discoveryWait = const Duration(seconds: 6),
    List<String>? lastResortHosts,
  }) : _api = api ?? NativeTransferApi(),
       _aliasOverride = alias,
       _defaultFolder = defaultFolder ?? defaultReceiveFolder,
       // The Android emulator reaches its host PC only through 10.0.2.2, and
       // its NAT hides mDNS. Mutual TLS still rejects any other listener.
       _lastResortHosts =
           lastResortHosts ?? (Platform.isAndroid ? ['10.0.2.2'] : const []);

  static const folderKey = 'mirquova.transfer.folder.v1';

  final PairingIdentityRepository identities;
  final PairingTrustRepository trustedPeers;
  final PairingSecretStore settings;
  final DiscoveryPort? discovery;
  final Duration receivePoll;
  final Duration retryDelay;
  final Duration discoveryWait;
  final TransferApi _api;
  final String? _aliasOverride;
  String? _alias;
  final Future<String?> Function() _defaultFolder;
  final List<String> _lastResortHosts;

  List<TrustedPeer> peers = const [];
  String? folder;

  bool _wanted = false;
  bool _armed = false;
  bool _arming = false;
  bool _disposed = false;
  List<TrustedPeer> _armedPeers = const [];
  Timer? _receiveTimer;
  Timer? _retryTimer;
  Timer? _presenceTimer;
  String? receiveProblem;
  TransferSnapshot incoming = const TransferSnapshot();
  TrustedPeer? incomingPeer;
  bool _addressRecorded = false;
  IncomingResult? _lastIncoming;

  TransferSnapshot outgoing = const TransferSnapshot();
  TrustedPeer? outgoingPeer;
  String? sendMessage;
  int _sendGeneration = 0;

  bool get receiving => _armed;
  bool get sending =>
      outgoingPeer != null &&
      outgoing.status != TransferStatus.idle &&
      !outgoing.finished;
  bool get incomingNeedsAnswer =>
      incoming.status == TransferStatus.awaitingApproval;

  /// The most recent finished incoming offer, cleared once read.
  IncomingResult? takeLastIncoming() {
    final value = _lastIncoming;
    _lastIncoming = null;
    return value;
  }

  Future<void> startReceiving() async {
    _wanted = true;
    _alias ??= _aliasOverride ?? await localDeviceName();
    await reloadPeers();
    await _arm();
  }

  /// Stops listening, except while an offer is open or files are moving.
  void pauseReceiving() {
    _wanted = false;
    _retryTimer?.cancel();
    _presenceTimer?.cancel();
    if (incoming.status == TransferStatus.awaitingApproval ||
        incoming.status == TransferStatus.transferring) {
      return;
    }
    _disarm();
    _notify();
  }

  Future<void> reloadPeers() async {
    try {
      peers = await trustedPeers.list();
    } on Object {
      peers = const [];
      receiveProblem = 'Trusted devices could not be read.';
    }
    if (_armed && !_samePeers(peers, _armedPeers) && !_busyReceiving) {
      _disarm();
      await _arm();
    }
    _notify();
  }

  Future<void> setFolder(String path) async {
    folder = path;
    await settings.write(folderKey, path);
    if (!_busyReceiving) {
      _disarm();
      await _arm();
    }
    _notify();
  }

  bool approve() {
    final accepted = _api.approve();
    _readIncoming();
    return accepted;
  }

  bool reject() {
    final declined = _api.reject();
    _readIncoming();
    return declined;
  }

  bool get _busyReceiving =>
      incoming.status == TransferStatus.awaitingApproval ||
      incoming.status == TransferStatus.transferring;

  Future<String?> _resolveFolder() async {
    String? saved;
    try {
      saved = await settings.read(folderKey);
    } on Object {
      saved = null;
    }
    final seen = <String>{};
    for (final path in [folder, saved, await _defaultFolder()]) {
      if (path == null || path.isEmpty || !seen.add(path)) continue;
      if (await _ensureWritableDirectory(path)) {
        folder = path;
        return path;
      }
    }
    return null;
  }

  /// Native receive writes with the same filesystem APIs as Dart. A folder
  /// that exists is not enough: public Downloads on Android can accept a
  /// Java mkdir and still refuse the `.mqpart` file Rust creates.
  Future<bool> _ensureWritableDirectory(String path) async {
    try {
      final directory = Directory(path);
      await directory.create(recursive: true);
      final probe = File(
        '$path${Platform.pathSeparator}.mqwrite-${DateTime.now().microsecondsSinceEpoch}',
      );
      await probe.writeAsBytes(const [1], flush: true);
      await probe.delete();
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _arm() async {
    if (!_wanted || _armed || _arming || _disposed) return;
    final current = peers;
    if (current.isEmpty) {
      receiveProblem = null;
      _notify();
      return;
    }
    _arming = true;
    try {
      final destination = await _resolveFolder();
      if (destination == null) {
        receiveProblem = 'Choose a folder for received files. The default folder could not be created.';
        return;
      }
      final identity = await identities.loadOrCreate();
      final config = jsonEncode({
        'local_ipv4': '0.0.0.0',
        'port': mirquovaTransferPort,
        'destination_directory': destination,
        'peer_ca_certificates_der_hex': [
          for (final peer in current) _hex(base64Decode(peer.certificateDer)),
        ],
      });
      final started = _api.startReceive(configJson: config, identity: identity);
      identity.clearPrivateKeyCopy();
      if (_disposed) return;
      if (!started) {
        receiveProblem = 'Receiving is paused because another app is using the transfer port. Close other Mirquova windows.';
        _retryTimer?.cancel();
        _retryTimer = Timer(retryDelay, () => unawaited(_arm()));
        return;
      }
      _armed = true;
      _armedPeers = current;
      receiveProblem = null;
      incoming = const TransferSnapshot(status: TransferStatus.listening);
      incomingPeer = null;
      _addressRecorded = false;
      _receiveTimer?.cancel();
      _receiveTimer = Timer.periodic(receivePoll, (_) => _readIncoming());
      _announce();
    } on Object {
      receiveProblem = 'Receiving could not start on this device.';
    } finally {
      _arming = false;
      _notify();
    }
  }

  void _disarm() {
    _receiveTimer?.cancel();
    _receiveTimer = null;
    if (_armed) _api.stopReceive();
    _armed = false;
    incoming = const TransferSnapshot();
    incomingPeer = null;
  }

  /// Keeps this device visible to paired devices whose saved address is
  /// stale. Visibility is untrusted; transfers still require mutual TLS.
  void _announce() {
    final port = discovery;
    final alias = _alias;
    if (port == null || alias == null || !PresenceState.validAlias(alias)) {
      return;
    }
    _presenceTimer?.cancel();
    void show() {
      if (_armed && _wanted && !port.snapshot.presence.active) {
        unawaited(port.makeDiscoverable(alias));
      }
    }

    show();
    _presenceTimer = Timer.periodic(const Duration(seconds: 30), (_) => show());
  }

  void _readIncoming() {
    if (!_armed || _disposed) return;
    final TransferSnapshot snapshot;
    try {
      snapshot = _api.readReceive();
    } on Object {
      _disarm();
      receiveProblem = 'The transfer status could not be read.';
      _notify();
      return;
    }
    final index = snapshot.peerIndex;
    if (index != null && index >= 0 && index < _armedPeers.length) {
      incomingPeer = _armedPeers[index];
      final address = snapshot.peerIpv4;
      if (!_addressRecorded && address != null) {
        _addressRecorded = true;
        unawaited(_recordAddress(incomingPeer!, address));
      }
    }
    final changed =
        snapshot.status != incoming.status ||
        snapshot.transferredBytes != incoming.transferredBytes;
    incoming = snapshot;
    if (snapshot.finished) {
      if (snapshot.files.isNotEmpty || incomingPeer != null) {
        unawaited(_finishIncoming(snapshot));
        return;
      }
      _disarm();
      _notify();
      if (_wanted) unawaited(_arm());
      return;
    }
    if (changed) _notify();
  }

  Future<void> _finishIncoming(TransferSnapshot snapshot) async {
    var savedTo = folder ?? '';
    if (snapshot.status == TransferStatus.completed && savedTo.isNotEmpty) {
      savedTo = await publishReceivedFiles(
        destination: savedTo,
        names: [for (final file in snapshot.files) file.name],
      );
    }
    if (_disposed) return;
    _lastIncoming = IncomingResult(
      snapshot: snapshot,
      senderAlias: incomingPeer?.alias ?? 'A paired device',
      folder: savedTo,
    );
    _disarm();
    _notify();
    if (_wanted) unawaited(_arm());
  }

  Future<void> _recordAddress(TrustedPeer peer, String address) async {
    if (peer.lanIpv4 == address) return;
    try {
      await trustedPeers.updateAddress(peer.fingerprintSha256, address);
      peers = await trustedPeers.list();
      _notify();
    } on Object {
      // A missing address update only means the next send may need discovery.
    }
  }

  Future<void> send({
    required TrustedPeer peer,
    required List<String> paths,
  }) async {
    if (paths.isEmpty) {
      sendMessage = 'Choose at least one file.';
      _notify();
      return;
    }
    final generation = ++_sendGeneration;
    _api.stopSend();
    outgoingPeer = peer;
    sendMessage = null;
    outgoing = const TransferSnapshot(status: TransferStatus.connecting);
    _notify();
    final tried = <String>{};
    final saved = peer.lanIpv4;
    var hosts = <String>[?saved];
    var result = const TransferSnapshot(
      status: TransferStatus.error,
      errorCode: 'network',
    );
    for (var round = 0; round < 2; round++) {
      for (final host in hosts) {
        if (!tried.add(host)) continue;
        result = await _sendTo(generation, peer, host, paths);
        if (generation != _sendGeneration) return;
        if (!_unreachable(result)) {
          _finishSend(result, peer);
          return;
        }
      }
      if (round == 0) {
        hosts = [...await _discoverAddresses(peer.alias), ..._lastResortHosts];
        if (generation != _sendGeneration) return;
      }
    }
    _finishSend(result, peer);
  }

  void cancelSend() {
    _sendGeneration++;
    _api.stopSend();
    outgoing = const TransferSnapshot(status: TransferStatus.stopped);
    sendMessage = transferStatusMessage(outgoing);
    _notify();
  }

  void clearSend() {
    if (sending) return;
    outgoing = const TransferSnapshot();
    outgoingPeer = null;
    sendMessage = null;
    _notify();
  }

  bool _unreachable(TransferSnapshot snapshot) =>
      snapshot.status == TransferStatus.error &&
      snapshot.errorCode == 'network' &&
      snapshot.files.every((file) => file.transferred == 0);

  void _finishSend(TransferSnapshot result, TrustedPeer peer) {
    outgoing = result;
    sendMessage = switch (result.status) {
      TransferStatus.completed => 'Sent to ${peer.alias}.',
      TransferStatus.rejected =>
        "${peer.alias} didn't accept the files. Nothing was sent.",
      _ when _unreachable(result) =>
        "Couldn't reach ${peer.alias}. Open Mirquova on it and keep both devices on the same Wi-Fi.",
      _ => transferStatusMessage(result),
    };
    _notify();
  }

  Future<TransferSnapshot> _sendTo(
    int generation,
    TrustedPeer peer,
    String host,
    List<String> paths,
  ) async {
    if (ManualEndpoint.parse(host, '$mirquovaTransferPort') == null) {
      return const TransferSnapshot(
        status: TransferStatus.error,
        errorCode: 'network',
      );
    }
    final identity = await identities.loadOrCreate();
    final config = jsonEncode({
      'peer_ipv4': host,
      'port': mirquovaTransferPort,
      'peer_ca_certificate_der_hex': _hex(base64Decode(peer.certificateDer)),
      'paths': paths,
    });
    final started = _api.startSend(configJson: config, identity: identity);
    identity.clearPrivateKeyCopy();
    if (!started) {
      return const TransferSnapshot(
        status: TransferStatus.error,
        errorCode: 'invalid_input',
      );
    }
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (_disposed || generation != _sendGeneration) return outgoing;
      final TransferSnapshot snapshot;
      try {
        snapshot = _api.readSend();
      } on Object {
        return const TransferSnapshot(status: TransferStatus.error);
      }
      if (snapshot.finished) return snapshot;
      outgoing = snapshot;
      _notify();
    }
  }

  Future<List<String>> _discoverAddresses(String alias) async {
    final port = discovery;
    if (port == null) return const [];
    final startedHere = port.snapshot.status != DiscoveryStatus.scanning;
    if (startedHere) await port.start();
    final deadline = DateTime.now().add(discoveryWait);
    final wanted = alias.trim().toLowerCase();
    try {
      while (DateTime.now().isBefore(deadline) && !_disposed) {
        final found = [
          for (final candidate in port.snapshot.peers)
            if (candidate.name.trim().toLowerCase() == wanted)
              ...candidate.addresses.where(
                (address) => ManualEndpoint.parse(address, '1') != null,
              ),
        ];
        if (found.isNotEmpty) return preferredLanAddresses(found.toSet());
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      return const [];
    } finally {
      if (startedHere) port.stop();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sendGeneration++;
    _retryTimer?.cancel();
    _presenceTimer?.cancel();
    _receiveTimer?.cancel();
    _api.stopSend();
    _api.stopReceive();
    super.dispose();
  }
}

bool _samePeers(List<TrustedPeer> a, List<TrustedPeer> b) =>
    a.length == b.length &&
    a
        .map((peer) => peer.fingerprintSha256)
        .toSet()
        .containsAll(b.map((peer) => peer.fingerprintSha256));

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
