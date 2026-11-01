import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../core/cast_state.dart';
import '../core/discovery_port.dart';
import 'native_transfer.dart';
import 'pairing_identity.dart';
import 'screen_capture.dart';

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
typedef _PushNative = Int32 Function(Pointer<Uint8>, Uint32);
typedef _Push = int Function(Pointer<Uint8>, int);
typedef _LatestNative = Pointer<Uint8> Function(Pointer<Uint32>);
typedef _Latest = Pointer<Uint8> Function(Pointer<Uint32>);
typedef _BytesFreeNative = Void Function(Pointer<Uint8>, Uint32);
typedef _BytesFree = void Function(Pointer<Uint8>, int);

abstract interface class CastApi {
  bool startReceive({
    required String configJson,
    required PairingIdentityMaterial identity,
  });
  bool startSend({
    required String configJson,
    required PairingIdentityMaterial identity,
  });
  CastSnapshot readReceive();
  CastSnapshot readSend();
  bool approve();
  bool reject();
  bool pushFrame(Uint8List jpeg);
  Uint8List? latestFrame();
  void stopReceive();
  void stopSend();
}

class NativeCastApi implements CastApi {
  NativeCastApi() {
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
      'mq_cast_receive_start',
    );
    _send = library.lookupFunction<_StartNative, _Start>('mq_cast_send_start');
    _approve = library.lookupFunction<_ActionNative, _Action>(
      'mq_cast_approve',
    );
    _reject = library.lookupFunction<_ActionNative, _Action>('mq_cast_reject');
    _receiveSnapshot = library.lookupFunction<_SnapshotNative, _Snapshot>(
      'mq_cast_receive_snapshot',
    );
    _sendSnapshot = library.lookupFunction<_SnapshotNative, _Snapshot>(
      'mq_cast_send_snapshot',
    );
    _push = library.lookupFunction<_PushNative, _Push>('mq_cast_push_frame');
    _latest = library.lookupFunction<_LatestNative, _Latest>(
      'mq_cast_latest_frame',
    );
    _bytesFree = library.lookupFunction<_BytesFreeNative, _BytesFree>(
      'mq_bytes_free',
    );
    _receiveStop = library.lookupFunction<_StopNative, _Stop>(
      'mq_cast_receive_stop',
    );
    _sendStop = library.lookupFunction<_StopNative, _Stop>('mq_cast_send_stop');
    _free = library.lookupFunction<_FreeNative, _Free>('mq_string_free');
  }

  late final _Start _receive;
  late final _Start _send;
  late final _Action _approve;
  late final _Action _reject;
  late final _Snapshot _receiveSnapshot;
  late final _Snapshot _sendSnapshot;
  late final _Push _push;
  late final _Latest _latest;
  late final _BytesFree _bytesFree;
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
  CastSnapshot readReceive() => _read(_receiveSnapshot);

  @override
  CastSnapshot readSend() => _read(_sendSnapshot);

  CastSnapshot _read(_Snapshot read) {
    final value = read();
    if (value == nullptr) {
      throw StateError('No native cast snapshot.');
    }
    try {
      return CastSnapshot.fromJson(
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
  bool pushFrame(Uint8List jpeg) {
    final pointer = _copy(jpeg);
    try {
      return _push(pointer, jpeg.length) == 1;
    } finally {
      calloc.free(pointer);
    }
  }

  @override
  Uint8List? latestFrame() {
    final length = calloc<Uint32>();
    try {
      final pointer = _latest(length);
      final size = length.value;
      if (pointer == nullptr || size == 0) return null;
      try {
        return Uint8List.fromList(pointer.asTypedList(size));
      } finally {
        _bytesFree(pointer, size);
      }
    } finally {
      calloc.free(length);
    }
  }

  @override
  void stopReceive() => _receiveStop();
  @override
  void stopSend() => _sendStop();
}

/// Keeps this device ready to receive a screen share from paired devices, and
/// sends this screen to one paired device at a time after they accept.
class CastService extends ChangeNotifier {
  CastService({
    required this.identities,
    required this.trustedPeers,
    CastApi? api,
    ScreenCapture? capture,
    this.discovery,
    String? alias,
    this.receivePoll = const Duration(milliseconds: 80),
    this.retryDelay = const Duration(seconds: 5),
    this.discoveryWait = const Duration(seconds: 6),
    this.frameInterval = const Duration(milliseconds: 80),
    List<String>? lastResortHosts,
  }) : _api = api ?? NativeCastApi(),
       _capture = capture ?? PlatformScreenCapture(),
       _aliasOverride = alias,
       _lastResortHosts =
           lastResortHosts ?? (Platform.isAndroid ? ['10.0.2.2'] : const []);

  final PairingIdentityRepository identities;
  final PairingTrustRepository trustedPeers;
  final DiscoveryPort? discovery;
  final Duration receivePoll;
  final Duration retryDelay;
  final Duration discoveryWait;
  final Duration frameInterval;
  final CastApi _api;
  final ScreenCapture _capture;
  final String? _aliasOverride;
  String? _alias;
  final List<String> _lastResortHosts;

  List<TrustedPeer> peers = const [];

  bool _wanted = false;
  bool _armed = false;
  bool _arming = false;
  bool _disposed = false;
  List<TrustedPeer> _armedPeers = const [];
  Timer? _receiveTimer;
  Timer? _retryTimer;
  Timer? _presenceTimer;
  String? receiveProblem;
  CastSnapshot incoming = const CastSnapshot();
  TrustedPeer? incomingPeer;
  bool _addressRecorded = false;
  Uint8List? incomingFrame;
  String? lastIncomingMessage;

  CastSnapshot outgoing = const CastSnapshot();
  TrustedPeer? outgoingPeer;
  String? sendMessage;
  int _sendGeneration = 0;

  bool get receiving => _armed;
  bool get sending =>
      outgoingPeer != null &&
      outgoing.status != CastStatus.idle &&
      !outgoing.finished;
  bool get incomingNeedsAnswer =>
      incoming.status == CastStatus.awaitingApproval;
  bool get incomingLive => incoming.status == CastStatus.casting;
  bool get captureSupported => _capture.supported;

  Future<void> startReceiving() async {
    _wanted = true;
    _alias ??= _aliasOverride ?? await localDeviceName();
    await reloadPeers();
    await _arm();
  }

  void pauseReceiving() {
    _wanted = false;
    _retryTimer?.cancel();
    _presenceTimer?.cancel();
    if (incomingNeedsAnswer || incomingLive) return;
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
    if (_armed &&
        !_samePeers(peers, _armedPeers) &&
        !incomingNeedsAnswer &&
        !incomingLive) {
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

  void stopIncoming() {
    _disarm();
    incoming = const CastSnapshot(status: CastStatus.stopped);
    incomingFrame = null;
    _notify();
    if (_wanted) unawaited(_arm());
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
      final identity = await identities.loadOrCreate();
      final config = jsonEncode({
        'local_ipv4': '0.0.0.0',
        'port': mirquovaCastPort,
        'peer_ca_certificates_der_hex': [
          for (final peer in current) _hex(base64Decode(peer.certificateDer)),
        ],
      });
      final started = _api.startReceive(configJson: config, identity: identity);
      identity.clearPrivateKeyCopy();
      if (_disposed) return;
      if (!started) {
        receiveProblem = 'Casting is paused because another app is using the cast port. Close other Mirquova windows.';
        _retryTimer?.cancel();
        _retryTimer = Timer(retryDelay, () => unawaited(_arm()));
        return;
      }
      _armed = true;
      _armedPeers = current;
      receiveProblem = null;
      incoming = const CastSnapshot(status: CastStatus.listening);
      incomingPeer = null;
      incomingFrame = null;
      _addressRecorded = false;
      _receiveTimer?.cancel();
      _receiveTimer = Timer.periodic(receivePoll, (_) => _readIncoming());
      _announce();
    } on Object {
      receiveProblem = 'Screen sharing could not start on this device.';
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
    incoming = const CastSnapshot();
    incomingPeer = null;
    incomingFrame = null;
  }

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
    final CastSnapshot snapshot;
    try {
      snapshot = _api.readReceive();
    } on Object {
      _disarm();
      receiveProblem = 'The cast status could not be read.';
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
    if (snapshot.status == CastStatus.casting) {
      incomingFrame = _api.latestFrame() ?? incomingFrame;
    }
    final changed =
        snapshot.status != incoming.status ||
        snapshot.frames != incoming.frames;
    incoming = snapshot;
    if (snapshot.finished) {
      lastIncomingMessage = switch (snapshot.status) {
        CastStatus.rejected when snapshot.errorCode == 'no_answer' =>
          'A screen-share request from ${incomingPeer?.alias ?? 'a paired device'} expired.',
        CastStatus.rejected =>
          'Declined a screen share from ${incomingPeer?.alias ?? 'a paired device'}.',
        _ =>
          'Screen share from ${incomingPeer?.alias ?? 'a paired device'} ended. ${castStatusMessage(snapshot)}',
      };
      _disarm();
      _notify();
      if (_wanted) unawaited(_arm());
      return;
    }
    if (changed) _notify();
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

  Future<void> startCast({required TrustedPeer peer}) async {
    if (!_capture.supported) {
      sendMessage = 'Screen capture is not available on this device.';
      outgoing = const CastSnapshot(
        status: CastStatus.error,
        errorCode: 'capture',
      );
      _notify();
      return;
    }
    final generation = ++_sendGeneration;
    _api.stopSend();
    outgoingPeer = peer;
    sendMessage = null;
    outgoing = const CastSnapshot(status: CastStatus.connecting);
    _notify();
    final allowed = await _capture.start();
    if (generation != _sendGeneration) return;
    if (!allowed) {
      outgoing = const CastSnapshot(
        status: CastStatus.error,
        errorCode: 'capture',
      );
      sendMessage = 'Screen capture was not allowed. Nothing was sent.';
      _notify();
      return;
    }
    final tried = <String>{};
    final saved = peer.lanIpv4;
    var hosts = <String>[?saved];
    var result = const CastSnapshot(
      status: CastStatus.error,
      errorCode: 'network',
    );
    for (var round = 0; round < 2; round++) {
      for (final host in hosts) {
        if (!tried.add(host)) continue;
        result = await _sendTo(generation, peer, host);
        if (generation != _sendGeneration) return;
        if (!_unreachable(result)) {
          await _finishSend(result, peer);
          return;
        }
      }
      if (round == 0) {
        hosts = [...await _discoverAddresses(peer.alias), ..._lastResortHosts];
        if (generation != _sendGeneration) return;
      }
    }
    await _finishSend(result, peer);
  }

  void stopOutgoing() {
    _sendGeneration++;
    _api.stopSend();
    unawaited(_capture.stop());
    outgoing = const CastSnapshot(status: CastStatus.stopped);
    sendMessage = castStatusMessage(outgoing);
    _notify();
  }

  void clearSend() {
    if (sending) return;
    outgoing = const CastSnapshot();
    outgoingPeer = null;
    sendMessage = null;
    _notify();
  }

  String? takeLastIncomingMessage() {
    final value = lastIncomingMessage;
    lastIncomingMessage = null;
    return value;
  }

  bool _unreachable(CastSnapshot snapshot) =>
      snapshot.status == CastStatus.error &&
      snapshot.errorCode == 'network' &&
      snapshot.frames == 0;

  Future<void> _finishSend(CastSnapshot result, TrustedPeer peer) async {
    await _capture.stop();
    outgoing = result;
    sendMessage = switch (result.status) {
      CastStatus.stopped => 'Stopped sharing to ${peer.alias}.',
      CastStatus.rejected => "${peer.alias} didn't accept the screen share.",
      _ when _unreachable(result) =>
        "Couldn't reach ${peer.alias}. Open Mirquova on it and keep both devices on the same Wi-Fi.",
      _ => castStatusMessage(result),
    };
    _notify();
  }

  Future<CastSnapshot> _sendTo(
    int generation,
    TrustedPeer peer,
    String host,
  ) async {
    if (ManualEndpoint.parse(host, '$mirquovaCastPort') == null) {
      return const CastSnapshot(status: CastStatus.error, errorCode: 'network');
    }
    final identity = await identities.loadOrCreate();
    final config = jsonEncode({
      'peer_ipv4': host,
      'port': mirquovaCastPort,
      'peer_ca_certificate_der_hex': _hex(base64Decode(peer.certificateDer)),
      'width': 1280,
      'height': 720,
    });
    final started = _api.startSend(configJson: config, identity: identity);
    identity.clearPrivateKeyCopy();
    if (!started) {
      return const CastSnapshot(
        status: CastStatus.error,
        errorCode: 'invalid_input',
      );
    }
    while (true) {
      await Future<void>.delayed(frameInterval);
      if (_disposed || generation != _sendGeneration) return outgoing;
      final CastSnapshot snapshot;
      try {
        snapshot = _api.readSend();
      } on Object {
        return const CastSnapshot(status: CastStatus.error);
      }
      if (snapshot.status == CastStatus.casting) {
        final frame = await _capture.captureFrame();
        if (frame != null) _api.pushFrame(frame);
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
    unawaited(_capture.stop());
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
