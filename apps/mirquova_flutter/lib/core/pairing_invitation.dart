import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'discovery_port.dart';

const maxPairingInvitationBytes = 2048;
const maxIdentityCaCertificateBytes = 512;

/// Parsed v2 bootstrap data. This is untrusted input, not an authenticated peer.
class PairingInvitation {
  PairingInvitation._({
    required this.endpoint,
    required List<int> identityCaCertificateDer,
    required List<int> secret,
    required this.ttlSeconds,
    required List<int> payloadBytes,
  }) : _identityCaCertificateDer = Uint8List.fromList(identityCaCertificateDer),
       _secret = Uint8List.fromList(secret),
       _payloadBytes = Uint8List.fromList(payloadBytes);

  final ManualEndpoint endpoint;
  final Uint8List _identityCaCertificateDer;
  final Uint8List _secret;
  Uint8List? _payloadBytes;
  final int ttlSeconds;

  Uint8List get identityCaCertificateDer =>
      Uint8List.fromList(_identityCaCertificateDer);

  /// A local display/comparison value. It does not authenticate the host until
  /// the user compares it with the host's out-of-band fingerprint.
  String get fingerprintSha256 =>
      sha256.convert(_identityCaCertificateDer).toString();

  /// Secret-bearing bytes for the TLS bootstrap request. Never log or persist.
  Uint8List get secretBytes => Uint8List.fromList(_secret);

  void dispose() {
    _secret.fillRange(0, _secret.length, 0);
    _identityCaCertificateDer.fillRange(0, _identityCaCertificateDer.length, 0);
    final payload = _payloadBytes;
    payload?.fillRange(0, payload.length, 0);
    _payloadBytes = null;
  }

  /// Transfers the original secret-bearing payload to the native join service.
  /// The returned bytes must never be logged or retained after the FFI call.
  Uint8List takePayload() {
    final payload = _payloadBytes;
    if (payload == null) {
      throw StateError('Invitation payload was already consumed.');
    }
    _payloadBytes = null;
    _secret.fillRange(0, _secret.length, 0);
    return payload;
  }

  @override
  String toString() => 'PairingInvitation { redacted }';

  static PairingInvitation parse(String input) {
    if (input.length > maxPairingInvitationBytes) {
      throw const FormatException('Invitation is too large.');
    }
    final encoded = utf8.encode(input);
    try {
      if (encoded.length > maxPairingInvitationBytes) {
        throw const FormatException('Invitation is too large.');
      }
      final value = jsonDecode(input);
      if (value is! Map<String, dynamic> ||
          !_hasExactKeys(value, const {
            'version',
            'purpose',
            'endpoint',
            'identity_ca_certificate_der_hex',
            'secret',
            'ttl_seconds',
          })) {
        throw const FormatException('Invitation fields are invalid.');
      }
      if (value['version'] != 2 || value['purpose'] != 'pairing') {
        throw const FormatException(
          'Invitation version or purpose is unsupported.',
        );
      }
      final endpointValue = value['endpoint'];
      if (endpointValue is! Map<String, dynamic> ||
          !_hasExactKeys(endpointValue, const {'ipv4', 'port'})) {
        throw const FormatException('Invitation endpoint is invalid.');
      }
      final address = endpointValue['ipv4'];
      final port = endpointValue['port'];
      if (address is! String || port is! int || port < 1 || port > 65535) {
        throw const FormatException('Invitation endpoint is invalid.');
      }
      final endpoint = ManualEndpoint.parse(address, '$port');
      if (endpoint == null) {
        throw const FormatException(
          'Invitation endpoint is not a private IPv4 address.',
        );
      }

      final ttl = value['ttl_seconds'];
      if (ttl is! int || ttl < 1 || ttl > 120) {
        throw const FormatException('Invitation expiry is invalid.');
      }

      Uint8List? certificateBuffer;
      Uint8List? secretBuffer;
      try {
        final certificateHex = value['identity_ca_certificate_der_hex'];
        if (certificateHex is! String ||
            certificateHex.isEmpty ||
            certificateHex.length.isOdd ||
            certificateHex.length > maxIdentityCaCertificateBytes * 2 ||
            !RegExp(r'^[0-9a-f]+$').hasMatch(certificateHex)) {
          throw const FormatException(
            'Invitation certificate encoding is invalid.',
          );
        }
        final certificate = _decodeHex(certificateHex);
        certificateBuffer = certificate;

        final secretHex = value['secret'];
        if (secretHex is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(secretHex)) {
          throw const FormatException('Invitation secret encoding is invalid.');
        }
        final secret = _decodeHex(secretHex);
        secretBuffer = secret;
        if (secret.every((byte) => byte == 0)) {
          throw const FormatException('Invitation secret is invalid.');
        }

        return PairingInvitation._(
          endpoint: endpoint,
          identityCaCertificateDer: certificate,
          secret: secret,
          ttlSeconds: ttl,
          payloadBytes: encoded,
        );
      } finally {
        certificateBuffer?.fillRange(0, certificateBuffer.length, 0);
        secretBuffer?.fillRange(0, secretBuffer.length, 0);
      }
    } finally {
      encoded.fillRange(0, encoded.length, 0);
    }
  }
}

bool _hasExactKeys(Map<String, dynamic> value, Set<String> expected) =>
    value.length == expected.length && value.keys.toSet().containsAll(expected);

Uint8List _decodeHex(String value) {
  final bytes = Uint8List(value.length ~/ 2);
  for (var index = 0; index < value.length; index += 2) {
    bytes[index ~/ 2] = int.parse(value.substring(index, index + 2), radix: 16);
  }
  return bytes;
}
