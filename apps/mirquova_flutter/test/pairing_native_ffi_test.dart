import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/adapters/pairing_identity.dart';
import 'package:mirquova/adapters/pairing_transport.dart';
import 'package:mirquova/core/discovery_port.dart';
import 'package:mirquova/core/pairing_invitation.dart';

void main() {
  const libraryPath = String.fromEnvironment('MIRQUOVA_CORE_LIBRARY');

  test(
    'native ABI rejects a wrong fingerprint before opening a connection',
    () {
      final identities = FfiPairingIdentityApi();
      final pairing = FfiPairingTransportApi();
      final identity = identities.create();
      try {
        final payload = jsonEncode({
          'version': 2,
          'purpose': 'pairing',
          'endpoint': {'ipv4': '192.168.1.20', 'port': 45833},
          'identity_ca_certificate_der_hex': _encodeHex(
            identity.certificateDer,
          ),
          'secret': '01' * 32,
          'ttl_seconds': 120,
        });
        expect(
          pairing.startJoin(
            invitationPayload: Uint8List.fromList(utf8.encode(payload)),
            confirmedFingerprintSha256: '00' * 32,
            alias: 'FFI probe',
            identity: identity,
          ),
          isFalse,
        );
        expect(pairing.read().status, PairingStatus.idle);
      } finally {
        identity.clearPrivateKeyCopy();
      }
    },
    skip: libraryPath.isEmpty ? 'Requires the compiled Rust core.' : false,
  );

  test('native ABI rejects public host addresses before listener creation', () {
    final identities = FfiPairingIdentityApi();
    final pairing = FfiPairingTransportApi();
    final identity = identities.create();
    try {
      expect(
        () => pairing.startHost(
          localIpv4: '8.8.8.8',
          port: 0,
          hostAlias: 'FFI probe',
          identity: identity,
        ),
        throwsStateError,
      );
      expect(pairing.read().status, PairingStatus.idle);
    } finally {
      identity.clearPrivateKeyCopy();
    }
  }, skip: libraryPath.isEmpty ? 'Requires the compiled Rust core.' : false);

  test(
    'native ABI starts and stops a private-interface host listener',
    () async {
      final identities = FfiPairingIdentityApi();
      final pairing = FfiPairingTransportApi();
      final identity = identities.create();
      try {
        final interfaces = await NetworkInterface.list(
          includeLoopback: false,
          type: InternetAddressType.IPv4,
        );
        final address = interfaces
            .expand((interface) => interface.addresses)
            .map((address) => address.address)
            .where((address) => ManualEndpoint.parse(address, '1') != null)
            .firstOrNull;
        if (address == null) {
          markTestSkipped(
            'No RFC1918 IPv4 interface is available on this runner.',
          );
          return;
        }

        final payload = pairing.startHost(
          localIpv4: address,
          port: 0,
          hostAlias: 'FFI probe',
          identity: identity,
        );
        final invitation = PairingInvitation.parse(payload);
        expect(invitation.endpoint.address, address);
        expect(invitation.endpoint.port, inInclusiveRange(1, 65535));
        expect(pairing.read().status, PairingStatus.waitingForPeer);
        invitation.dispose();
        pairing.stop();
        expect(pairing.read().status, PairingStatus.idle);
      } finally {
        pairing.stop();
        identity.clearPrivateKeyCopy();
      }
    },
    skip: libraryPath.isEmpty ? 'Requires the compiled Rust core.' : false,
  );
}

String _encodeHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
