import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/adapters/native_transfer.dart';
import 'package:mirquova/adapters/pairing_identity.dart';
import 'package:mirquova/core/discovery_port.dart';
import 'package:mirquova/core/transfer_state.dart';
import 'package:mirquova/features/transfer/incoming_transfer.dart';
import 'package:mirquova/features/transfer/transfer_page.dart';
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

class _Api implements TransferApi {
  final receiveConfigs = <Map<String, dynamic>>[];
  final sendConfigs = <Map<String, dynamic>>[];
  TransferSnapshot receive = const TransferSnapshot(
    status: TransferStatus.listening,
  );
  TransferSnapshot Function(String host) sendResult = (_) =>
      const TransferSnapshot(status: TransferStatus.completed);
  String? _host;
  int approvals = 0;

  @override
  bool startReceive({
    required String configJson,
    required PairingIdentityMaterial identity,
  }) {
    receiveConfigs.add(jsonDecode(configJson) as Map<String, dynamic>);
    receive = const TransferSnapshot(status: TransferStatus.listening);
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
  TransferSnapshot readReceive() => receive;
  @override
  TransferSnapshot readSend() => sendResult(_host!);
  @override
  bool approve() {
    approvals++;
    return true;
  }

  @override
  bool reject() => true;
  @override
  void stopReceive() {}
  @override
  void stopSend() {}
}

class _Discovery extends DiscoveryPort {
  _Discovery(this.peers);
  final List<PeerCandidate> peers;
  bool scanning = false;
  @override
  DiscoverySnapshot get snapshot => DiscoverySnapshot(
    status: scanning ? DiscoveryStatus.scanning : DiscoveryStatus.idle,
    peers: scanning ? peers : const [],
  );
  @override
  Future<void> start() async => scanning = true;
  @override
  void stop() => scanning = false;
  @override
  Future<void> makeDiscoverable(String alias) async {}
  @override
  void hide() {}
}

Future<void> _until(FutureOr<bool> Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (await ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late _Store store;
  late _Api api;
  late Directory folder;
  late PairingTrustRepository trust;

  setUp(() async {
    store = _Store();
    api = _Api();
    folder = await Directory.systemTemp.createTemp('mirquova-receive-');
    trust = PairingTrustRepository(store: store);
  });

  tearDown(() async {
    if (await folder.exists()) await folder.delete(recursive: true);
  });

  TransferService service({
    DiscoveryPort? discovery,
    Future<String> Function({
      required String destination,
      required List<String> names,
    })?
    publishFiles,
  }) => TransferService(
    identities: PairingIdentityRepository(api: _Identity(), store: store),
    trustedPeers: trust,
    settings: store,
    api: api,
    discovery: discovery,
    publishFiles: publishFiles,
    alias: 'Desk PC',
    defaultFolder: () async => folder.path,
    receivePoll: const Duration(milliseconds: 10),
    discoveryWait: const Duration(milliseconds: 200),
    lastResortHosts: const [],
  );

  test('receiving starts on every interface with no setup', () async {
    await trust.trust(alias: 'Pixel', certificateDer: [9, 9, 9]);
    final transfer = service();
    addTearDown(transfer.dispose);

    await transfer.startReceiving();

    expect(transfer.receiving, isTrue);
    expect(api.receiveConfigs.single['local_ipv4'], '0.0.0.0');
    expect(api.receiveConfigs.single['port'], mirquovaTransferPort);
    expect(api.receiveConfigs.single['destination_directory'], folder.path);
  });

  test('without a paired device nothing listens', () async {
    final transfer = service();
    addTearDown(transfer.dispose);
    await transfer.startReceiving();
    expect(transfer.receiving, isFalse);
    expect(api.receiveConfigs, isEmpty);
  });

  test('an offer names the verified sender, waits for approval, then listens again', () async {
    await trust.trust(
      alias: 'Pixel',
      certificateDer: [9, 9, 9],
      lanIpv4: '192.168.1.40',
    );
    final transfer = service();
    addTearDown(transfer.dispose);
    await transfer.startReceiving();

    api.receive = const TransferSnapshot(
      status: TransferStatus.awaitingApproval,
      peerIndex: 0,
      peerIpv4: '192.168.1.41',
      files: [
        TransferFileSnapshot(
          name: 'photo.jpg',
          size: 2048,
          transferred: 0,
          state: TransferFileState.pending,
        ),
      ],
    );
    await _until(() => transfer.incomingNeedsAnswer);
    expect(transfer.incomingNeedsAnswer, isTrue);
    expect(transfer.incomingPeer?.alias, 'Pixel');
    await _until(
      () async => (await trust.list()).single.lanIpv4 == '192.168.1.41',
    );
    expect((await trust.list()).single.lanIpv4, '192.168.1.41');
    expect(api.approvals, 0);

    transfer.approve();
    expect(api.approvals, 1);
    api.receive = const TransferSnapshot(
      status: TransferStatus.completed,
      peerIndex: 0,
      files: [
        TransferFileSnapshot(
          name: 'photo.jpg',
          size: 2048,
          transferred: 2048,
          state: TransferFileState.verified,
        ),
      ],
    );
    await _until(() => api.receiveConfigs.length == 2 && transfer.receiving);

    final result = transfer.takeLastIncoming();
    expect(result?.senderAlias, 'Pixel');
    expect(incomingResultMessage(result!), contains('Received 1 file'));
    expect(api.receiveConfigs, hasLength(2));
    expect(transfer.receiving, isTrue);
  });

  test(
    'a completed receive publishes files only once while the copy is pending',
    () async {
      await trust.trust(alias: 'Pixel', certificateDer: [9, 9, 9]);
      final publishResult = Completer<String>();
      var publishCalls = 0;
      final transfer = service(
        publishFiles: ({required destination, required names}) {
          publishCalls++;
          expect(names, ['video.mp4']);
          return publishResult.future;
        },
      );
      addTearDown(transfer.dispose);
      await transfer.startReceiving();

      api.receive = const TransferSnapshot(
        status: TransferStatus.completed,
        files: [
          TransferFileSnapshot(
            name: 'video.mp4',
            size: 2048,
            transferred: 2048,
            state: TransferFileState.verified,
          ),
        ],
      );
      await _until(() => publishCalls == 1);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(publishCalls, 1);

      publishResult.complete(folder.path);
      await _until(() => api.receiveConfigs.length == 2 && transfer.receiving);
      expect(publishCalls, 1);
    },
  );

  test('a stale saved address falls back to the discovered one', () async {
    await trust.trust(
      alias: 'Pixel',
      certificateDer: [9, 9, 9],
      lanIpv4: '192.168.1.40',
    );
    api.sendResult = (host) => host == '192.168.1.40'
        ? const TransferSnapshot(
            status: TransferStatus.error,
            errorCode: 'network',
          )
        : const TransferSnapshot(status: TransferStatus.completed);
    final discovery = _Discovery(const [
      PeerCandidate(
        id: 'pixel',
        name: 'Pixel',
        addresses: ['192.168.1.77'],
        port: 0,
      ),
    ]);
    addTearDown(discovery.dispose);
    final transfer = service(discovery: discovery);
    addTearDown(transfer.dispose);
    await transfer.reloadPeers();

    await transfer.send(peer: transfer.peers.single, paths: ['a.txt']);

    expect(
      [for (final c in api.sendConfigs) c['peer_ipv4']],
      ['192.168.1.40', '192.168.1.77'],
    );
    expect(transfer.outgoing.status, TransferStatus.completed);
    expect(transfer.sendMessage, 'Sent to Pixel.');
    expect(discovery.scanning, isFalse);
  });

  test('a peer with no saved address still gets a last-resort host', () async {
    await trust.trust(alias: 'Desk PC', certificateDer: [9, 9, 9]);
    final transfer = TransferService(
      identities: PairingIdentityRepository(api: _Identity(), store: store),
      trustedPeers: trust,
      settings: store,
      api: api,
      defaultFolder: () async => folder.path,
      lastResortHosts: const ['10.0.2.2'],
    );
    addTearDown(transfer.dispose);
    await transfer.reloadPeers();

    await transfer.send(peer: transfer.peers.single, paths: ['a.txt']);

    expect(api.sendConfigs.single['peer_ipv4'], '10.0.2.2');
    expect(transfer.outgoing.status, TransferStatus.completed);
  });

  test('an unreachable device gets a plain next step', () async {
    await trust.trust(
      alias: 'Pixel',
      certificateDer: [9, 9, 9],
      lanIpv4: '192.168.1.40',
    );
    api.sendResult = (_) => const TransferSnapshot(
      status: TransferStatus.error,
      errorCode: 'network',
    );
    final transfer = service();
    addTearDown(transfer.dispose);
    await transfer.reloadPeers();

    await transfer.send(peer: transfer.peers.single, paths: ['a.txt']);

    expect(transfer.sendMessage, contains("Couldn't reach Pixel"));
  });

  testWidgets('the page sends chosen files with one tap on a device', (
    tester,
  ) async {
    await tester.runAsync(
      () => trust.trust(
        alias: 'Pixel',
        certificateDer: [9, 9, 9],
        lanIpv4: '192.168.1.40',
      ),
    );
    final transfer = service();
    addTearDown(transfer.dispose);
    await tester.runAsync(transfer.reloadPeers);

    await tester.pumpWidget(
      MaterialApp(
        theme: mirquovaTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: TransferPage(
              service: transfer,
              onOpenPair: () {},
              pickFiles: () async => const [
                PickedTransferFile(
                  path: 'C:/clip.mp4',
                  name: 'clip.mp4',
                  size: 4096,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Receive'), findsNothing);
    await tester.tap(find.text('Choose files'));
    await tester.pump();
    expect(find.text('clip.mp4'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Pixel'));
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pump();

    expect(api.sendConfigs.single['paths'], ['C:/clip.mp4']);
    expect(find.text('Sent to Pixel'), findsOneWidget);
  });

  testWidgets('with no paired device the page offers pairing', (tester) async {
    final transfer = service();
    addTearDown(transfer.dispose);
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransferPage(
            service: transfer,
            onOpenPair: () => opened = true,
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.tap(find.text('Pair a device'));
    expect(opened, isTrue);
  });
}
