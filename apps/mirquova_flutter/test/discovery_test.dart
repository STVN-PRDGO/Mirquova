import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/core/discovery_port.dart';

void main() {
  test(
    'manual fallback accepts only private IPv4 and valid explicit ports',
    () {
      for (final address in [
        '10.0.0.1',
        '172.16.2.3',
        '172.31.255.2',
        '192.168.1.20',
      ]) {
        expect(ManualEndpoint.parse(address, '45833')?.address, address);
      }
      for (final address in [
        '8.8.8.8',
        '127.0.0.1',
        '224.0.0.251',
        '0.0.0.0',
        '169.254.1.2',
        '172.32.0.1',
        'https://192.168.1.1',
        '192.168.1.1/file',
        'user@192.168.1.1',
        'localhost',
        '192.168.01.1',
        '192.168.256.1',
        '::1',
        '192.168.1',
      ]) {
        expect(ManualEndpoint.parse(address, '45833'), isNull, reason: address);
      }
      for (final port in ['0', '65536', '-1', 'abc', '', '1.5', '000001']) {
        expect(ManualEndpoint.parse('192.168.1.1', port), isNull, reason: port);
      }
      expect(
        ManualEndpoint.parse(' 192.168.1.20 ', '65535')?.key,
        '192.168.1.20:65535',
      );
    },
  );

  test('native snapshots reject incompatible ABI and trust escalation', () {
    final peer = {
      'id': 'a',
      'name': 'Test',
      'addresses': ['10.0.0.1'],
      'port': 0,
      'verified': false,
    };
    final json = <String, dynamic>{
      'abi_version': 2,
      'status': 'complete',
      'peers': {'a': peer},
      'error': null,
      'presence': {
        'status': 'hidden',
        'alias': null,
        'remaining_seconds': 0,
        'error': null,
      },
    };
    expect(DiscoverySnapshot.fromJson(json).peers.single.verified, isFalse);
    expect(
      () => DiscoverySnapshot.fromJson({...json, 'abi_version': 99}),
      throwsFormatException,
    );
    expect(
      () => PeerCandidate.fromJson({...peer, 'verified': true}),
      throwsFormatException,
    );
    expect(
      () => DiscoverySnapshot.fromJson({...json, 'status': 'invented'}),
      throwsArgumentError,
    );
  });
  test(
    'visible names are bounded UTF-8 and reject control or bidi characters',
    () {
      expect(PresenceState.validAlias('Living room TV'), isTrue);
      for (final alias in [
        '',
        '   ',
        'a\n',
        'a\u202eb',
        'x' * 65,
        '\u{1f600}' * 17,
      ]) {
        expect(PresenceState.validAlias(alias), isFalse);
      }
    },
  );
}
