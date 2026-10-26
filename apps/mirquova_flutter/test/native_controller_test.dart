import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/adapters/native_discovery.dart';
import 'package:mirquova/core/discovery_port.dart';

class MemoryApi implements NativeDiscoveryApi {
  DiscoverySnapshot value = const DiscoverySnapshot();
  int scans = 0, announcements = 0;
  @override
  DiscoverySnapshot read() => value;
  @override
  int startScan() {
    scans++;
    value = value.copyWith(status: DiscoveryStatus.scanning);
    return 1;
  }

  @override
  void stopScan() {
    value = value.copyWith(status: DiscoveryStatus.stopped);
  }

  @override
  int startPresence(String alias) {
    announcements++;
    value = value.copyWith(
      presence: PresenceState(status: PresenceStatus.visible, alias: alias),
    );
    return 1;
  }

  @override
  void stopPresence() {
    value = value.copyWith(presence: const PresenceState());
  }
}

class ControlledAccess implements MulticastAccess {
  int acquires = 0, releases = 0;
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<void> acquire() async {
    acquires++;
    if (gate != null) {
      await gate!.future;
    }
    if (fail) {
      throw StateError('permission denied');
    }
  }

  @override
  Future<void> release() async {
    releases++;
  }
}

void main() {
  test(
    'scan and presence share one lease until both operations stop',
    () async {
      final api = MemoryApi();
      final access = ControlledAccess();
      final port = NativeDiscovery(api: api, multicast: access);
      addTearDown(port.dispose);
      expect(api.scans + api.announcements, 0);
      await Future.wait([port.makeDiscoverable('Office'), port.start()]);
      expect(access.acquires, 1);
      port.stop();
      await Future<void>.delayed(Duration.zero);
      expect(access.releases, 0);
      expect(port.snapshot.presence.status, PresenceStatus.visible);
      port.hide();
      await Future<void>.delayed(Duration.zero);
      expect(access.releases, 1);
    },
  );
  test(
    'hide during an outstanding acquire never announces afterwards',
    () async {
      final api = MemoryApi();
      final access = ControlledAccess()..gate = Completer<void>();
      final port = NativeDiscovery(api: api, multicast: access);
      addTearDown(port.dispose);
      final operation = port.makeDiscoverable('Private alias');
      await Future<void>.delayed(Duration.zero);
      port.hide();
      access.gate!.complete();
      await operation;
      expect(api.announcements, 0);
      expect(access.releases, 1);
      expect(port.snapshot.presence.status, PresenceStatus.hidden);
    },
  );
  test(
    'dispose during an acquire releases the eventual lock without scanning',
    () async {
      final api = MemoryApi();
      final access = ControlledAccess()..gate = Completer<void>();
      final port = NativeDiscovery(api: api, multicast: access);
      final operation = port.start();
      await Future<void>.delayed(Duration.zero);
      port.dispose();
      access.gate!.complete();
      await operation;
      expect(api.scans, 0);
      expect(access.releases, 1);
    },
  );
  test('permission failures do not announce and can be retried', () async {
    final api = MemoryApi();
    final access = ControlledAccess()..fail = true;
    final port = NativeDiscovery(api: api, multicast: access);
    addTearDown(port.dispose);
    await port.makeDiscoverable('Office');
    expect(api.announcements, 0);
    expect(port.snapshot.presence.status, PresenceStatus.error);
    access.fail = false;
    await port.makeDiscoverable('Office');
    expect(api.announcements, 1);
    expect(port.snapshot.presence.status, PresenceStatus.visible);
  });
}
