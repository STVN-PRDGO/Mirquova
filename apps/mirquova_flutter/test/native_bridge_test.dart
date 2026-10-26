import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/adapters/native_discovery.dart';
import 'package:mirquova/core/discovery_port.dart';

void main() {
  const path = String.fromEnvironment('MIRQUOVA_CORE_LIBRARY');
  test(
    'compiled native ABI loads without opening a discovery session',
    () {
      final port = NativeDiscovery();
      expect(port.snapshot.status, DiscoveryStatus.idle);
      expect(port.snapshot.peers, isEmpty);
      port.dispose();
    },
    skip: path.isEmpty
        ? 'Run with --dart-define=MIRQUOVA_CORE_LIBRARY=<compiled library>'
        : false,
  );
}
