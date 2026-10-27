import 'package:crypto/crypto.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/core/pairing_invitation.dart';

String invitation({
  String address = '192.168.1.8',
  int port = 45833,
  String certificate = '3000',
  String? secret,
  int ttl = 120,
  int version = 2,
  String purpose = 'pairing',
}) =>
    '{"version":$version,"purpose":"$purpose","endpoint":{"ipv4":"$address","port":$port},"identity_ca_certificate_der_hex":"$certificate","secret":"${secret ?? _hexByte(0xb2, 32)}","ttl_seconds":$ttl}';

String _hexByte(int byte, int count) =>
    List<String>.filled(count, byte.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test(
    'parses bounded v2 payload and computes fingerprint from supplied DER',
    () {
      final parsed = PairingInvitation.parse(invitation());
      expect(parsed.endpoint.key, '192.168.1.8:45833');
      expect(parsed.identityCaCertificateDer, [0x30, 0]);
      expect(parsed.fingerprintSha256, sha256.convert([0x30, 0]).toString());
      expect(parsed.secretBytes, List<int>.filled(32, 0xb2));
      expect(parsed.ttlSeconds, 120);
      expect(parsed.toString(), 'PairingInvitation { redacted }');
    },
  );

  test('accepts the maximum bounded certificate encoding', () {
    final parsed = PairingInvitation.parse(
      invitation(certificate: _hexByte(0x30, maxIdentityCaCertificateBytes)),
    );
    expect(parsed.identityCaCertificateDer, List<int>.filled(512, 0x30));
    expect(
      () => PairingInvitation.parse(
        invitation(
          certificate: _hexByte(0x30, maxIdentityCaCertificateBytes + 1),
        ),
      ),
      throwsFormatException,
    );
  });

  test('rejects oversized, unsupported, malformed and unsafe invitations', () {
    for (final input in [
      invitation(version: 1),
      invitation(purpose: 'transfer'),
      invitation(address: '8.8.8.8'),
      invitation(address: '127.0.0.1'),
      invitation(port: 0),
      invitation(certificate: ''),
      invitation(certificate: 'AA'),
      invitation(certificate: 'zz'),
      invitation(secret: _hexByte(0, 32)),
      invitation(secret: _hexByte(0xb2, 31)),
      invitation(ttl: 0),
      invitation(ttl: 121),
      invitation().replaceFirst(
        '"ttl_seconds":120',
        '"ttl_seconds":120,"extra":true',
      ),
      ' ' * (maxPairingInvitationBytes + 1),
    ]) {
      expect(() => PairingInvitation.parse(input), throwsFormatException);
    }
  });

  test('checks UTF-8 byte size before decoding large multibyte input', () {
    expect(
      () => PairingInvitation.parse('😀' * (maxPairingInvitationBytes ~/ 2)),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Invitation is too large.',
        ),
      ),
    );
  });

  test('returned secret bytes are copies so callers can clear their copy', () {
    final parsed = PairingInvitation.parse(invitation());
    final secret = parsed.secretBytes;
    secret.fillRange(0, secret.length, 0);
    expect(parsed.secretBytes, List<int>.filled(32, 0xb2));
  });

  test('join payload transfers bounded bytes and can be cleared by caller', () {
    final parsed = PairingInvitation.parse(invitation());
    final payload = parsed.takePayload();

    expect(utf8.decode(payload), invitation());
    expect(() => parsed.takePayload(), throwsStateError);
    payload.fillRange(0, payload.length, 0);
    expect(payload, everyElement(0));
  });

  test('dispose clears the secret, certificate and retained payload', () {
    final parsed = PairingInvitation.parse(invitation());
    parsed.dispose();

    expect(parsed.secretBytes, List<int>.filled(32, 0));
    expect(parsed.identityCaCertificateDer, [0, 0]);
    expect(() => parsed.takePayload(), throwsStateError);
  });
}
