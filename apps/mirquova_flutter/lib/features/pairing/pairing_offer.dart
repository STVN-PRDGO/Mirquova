import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/discovery_port.dart';

const mirquovaPairOfferPort = 40734;
const mirquovaPairListenPort = 40735;

class PairingOffer {
  PairingOffer._(this._server);
  final ServerSocket _server;
  String? payload;

  static Future<PairingOffer> start() async {
    final server = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      mirquovaPairOfferPort,
    );
    final offer = PairingOffer._(server);
    server.listen((socket) {
      final payload = offer.payload;
      if (payload == null) {
        socket.destroy();
        return;
      }
      socket.add(utf8.encode('$payload\n'));
      unawaited(socket.close());
    });
    return offer;
  }

  Future<void> close() async {
    payload = null;
    await _server.close();
  }

  static Future<String> fetch(List<String> addresses) async {
    final targets = preferredLanAddresses(addresses).toList();
    if (Platform.isAndroid) targets.add('10.0.2.2');
    for (final address in targets) {
      final reached = await _readOffer(address);
      if (reached != null) return _retarget(reached, address);
    }
    throw const SocketException('The other device did not answer.');
  }

  static Future<String?> _readOffer(String address) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        address,
        mirquovaPairOfferPort,
        timeout: const Duration(seconds: 2),
      );
      final bytes = <int>[];
      await for (final chunk in socket.timeout(const Duration(seconds: 2))) {
        bytes.addAll(chunk);
        if (bytes.length > 2048) return null;
      }
      if (bytes.isEmpty || bytes.length > 2048) return null;
      return utf8.decode(bytes).trim();
    } on Object {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  static String _retarget(String payload, String address) {
    final endpoint = RegExp('"ipv4":"[0-9.]+"').firstMatch(payload);
    if (endpoint == null) {
      throw const FormatException('Invitation endpoint is invalid.');
    }
    return payload.replaceRange(
      endpoint.start,
      endpoint.end,
      '"ipv4":"$address"',
    );
  }
}
