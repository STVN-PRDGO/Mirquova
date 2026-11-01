import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/adapters/native_cast.dart';
import 'package:mirquova/adapters/pairing_identity.dart';
import 'package:mirquova/adapters/screen_capture.dart';
import 'package:mirquova/core/cast_state.dart';
import 'package:mirquova/features/cast/cast_page.dart';
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

class _Api implements CastApi {
  final receiveConfigs = <Map<String, dynamic>>[];
  final sendConfigs = <Map<String, dynamic>>[];
  final pushed = <Uint8List>[];
  CastSnapshot receive = const CastSnapshot(status: CastStatus.listening);
  CastSnapshot Function(String host) sendResult = (_) =>
      const CastSnapshot(status: CastStatus.stopped);
  String? _host;
  int approvals = 0;
  Uint8List? frame;

  @override
  bool startReceive({
    required String configJson,
    required PairingIdentityMaterial identity,
  }) {
    receiveConfigs.add(jsonDecode(configJson) as Map<String, dynamic>);
    receive = const CastSnapshot(status: CastStatus.listening);
    return true;
  }

  @override
  bool startSend({
    required String configJson,
    required PairingIdentityMaterial identity,
  }) {
    final config = jsonDecode(configJson) as Map<String, dynamic>;
    sendConfigs.add(config);
    _host = config['peer_ipv4'] as String;
    return true;
  }

  @override
  CastSnapshot readReceive() => receive;
  @override
  CastSnapshot readSend() => sendResult(_host!);
  @override
  bool approve() {
    approvals++;
    return true;
  }

  @override
  bool reject() => true;
  @override
  bool pushFrame(Uint8List jpeg) {
    pushed.add(jpeg);
    return true;
  }

  @override
  Uint8List? latestFrame() => frame;
  @override
  void stopReceive() {}
  @override
  void stopSend() {}
}

class _Capture implements ScreenCapture {
  _Capture();
  bool allow = true;
  Uint8List? frame;
  bool started = false;
  @override
  bool get active => started;
  @override
  bool get supported => true;
  @override
  Future<bool> start() async {
    started = allow;
    return allow;
  }

  @override
  Future<Uint8List?> captureFrame() async => frame;
  @override
  Future<void> stop() async => started = false;
}

void main() {
  late _Store store;
  late _Api api;
  late PairingTrustRepository trust;

  setUp(() {
    store = _Store();
    api = _Api();
    trust = PairingTrustRepository(store: store);
  });

  CastService service({ScreenCapture? capture}) => CastService(
    identities: PairingIdentityRepository(api: _Identity(), store: store),
    trustedPeers: trust,
    api: api,
    capture: capture ?? _Capture(),
    alias: 'Desk PC',
    receivePoll: const Duration(milliseconds: 10),
    frameInterval: const Duration(milliseconds: 10),
    discoveryWait: const Duration(milliseconds: 50),
    lastResortHosts: const [],
  );

  test('receiving starts on every interface with no setup', () async {
    await trust.trust(alias: 'Pixel', certificateDer: [9, 9, 9]);
    final cast = service();
    addTearDown(cast.dispose);

    await cast.startReceiving();

    expect(cast.receiving, isTrue);
    expect(api.receiveConfigs.single['local_ipv4'], '0.0.0.0');
    expect(api.receiveConfigs.single['port'], mirquovaCastPort);
  });

  test('without a paired device nothing listens', () async {
    final cast = service();
    addTearDown(cast.dispose);
    await cast.startReceiving();
    expect(cast.receiving, isFalse);
    expect(api.receiveConfigs, isEmpty);
  });

  test('an offer names the verified sender and can be accepted', () async {
    await trust.trust(
      alias: 'Pixel',
      certificateDer: [9, 9, 9],
      lanIpv4: '192.168.1.40',
    );
    final cast = service();
    addTearDown(cast.dispose);
    await cast.startReceiving();

    api.receive = const CastSnapshot(
      status: CastStatus.awaitingApproval,
      peerIndex: 0,
      width: 1280,
      height: 720,
    );
    api.frame = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(cast.incomingNeedsAnswer, isTrue);
    expect(cast.incomingPeer?.alias, 'Pixel');

    cast.approve();
    expect(api.approvals, 1);
    api.receive = const CastSnapshot(
      status: CastStatus.casting,
      peerIndex: 0,
      frames: 2,
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(cast.incomingLive, isTrue);
    expect(cast.incomingFrame, isNotNull);
  });

  test('a stale saved address falls back to the last-resort host', () async {
    await trust.trust(
      alias: 'Pixel',
      certificateDer: [9, 9, 9],
      lanIpv4: '192.168.1.40',
    );
    api.sendResult = (host) => host == '192.168.1.40'
        ? const CastSnapshot(status: CastStatus.error, errorCode: 'network')
        : const CastSnapshot(status: CastStatus.stopped);
    final cast = CastService(
      identities: PairingIdentityRepository(api: _Identity(), store: store),
      trustedPeers: trust,
      api: api,
      capture: _Capture(),
      lastResortHosts: const ['10.0.2.2'],
      frameInterval: const Duration(milliseconds: 10),
    );
    addTearDown(cast.dispose);
    await cast.reloadPeers();

    await cast.startCast(peer: cast.peers.single);

    expect(
      [for (final config in api.sendConfigs) config['peer_ipv4']],
      ['192.168.1.40', '10.0.2.2'],
    );
    expect(cast.outgoing.status, CastStatus.stopped);
  });

  testWidgets('the page starts a cast with one tap on a device', (
    tester,
  ) async {
    await tester.runAsync(
      () => trust.trust(
        alias: 'Pixel',
        certificateDer: [9, 9, 9],
        lanIpv4: '192.168.1.40',
      ),
    );
    api.sendResult = (_) => const CastSnapshot(status: CastStatus.stopped);
    final cast = service();
    addTearDown(cast.dispose);
    await tester.runAsync(cast.reloadPeers);

    await tester.pumpWidget(
      MaterialApp(
        theme: mirquovaTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CastPage(
              service: cast,
              onOpenPair: () {},
              onOpenDevices: () {},
              onOpenRemote: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Start casting'), findsNothing);
    await tester.ensureVisible(find.text('Pixel'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Pixel'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    expect(api.sendConfigs.single['peer_ipv4'], '192.168.1.40');
    expect(api.sendConfigs.single['port'], mirquovaCastPort);
  });
}
