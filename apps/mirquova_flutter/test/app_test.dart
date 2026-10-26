import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/app.dart';
import 'package:mirquova/core/discovery_port.dart';

class TestDiscovery extends DiscoveryPort {
  DiscoverySnapshot value = const DiscoverySnapshot();
  int starts = 0;
  int stops = 0;
  @override
  DiscoverySnapshot get snapshot => value;
  @override
  Future<void> makeDiscoverable(String alias) async {
    value = value.copyWith(
      presence: PresenceState(
        status: PresenceStatus.visible,
        alias: alias,
        remainingSeconds: 120,
      ),
    );
    notifyListeners();
  }

  @override
  void hide() {
    value = value.copyWith(presence: const PresenceState());
    notifyListeners();
  }

  @override
  Future<void> start() async {
    starts++;
    value = value.copyWith(status: DiscoveryStatus.scanning);
    notifyListeners();
  }

  @override
  void stop() {
    stops++;
    value = value.copyWith(status: DiscoveryStatus.stopped);
    notifyListeners();
  }
}

void main() {
  Future<void> launch(
    WidgetTester tester,
    TestDiscovery port,
    Size size, {
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: MirquovaApp(discovery: port),
      ),
    );
    await tester.pump();
  }

  testWidgets('no automatic network scan; scan and stop have visible states', (
    tester,
  ) async {
    final port = TestDiscovery();
    await launch(tester, port, const Size(1280, 800));
    expect(port.starts, 0);
    expect(find.text('No devices listed yet'), findsOneWidget);
    await tester.tap(find.text('Scan nearby'));
    await tester.pump();
    expect(port.starts, 1);
    expect(find.text('Stop scan'), findsOneWidget);
    await tester.tap(find.text('Stop scan'));
    await tester.pump();
    expect(port.stops, 1);
    expect(find.text('Scan stopped'), findsOneWidget);
  });

  testWidgets(
    'manual address form keeps invalid input and adds only a local candidate',
    (tester) async {
      final port = TestDiscovery();
      await launch(tester, port, const Size(1280, 800));
      await tester.tap(find.text('Add LAN address'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'https://example.com',
      );
      await tester.tap(find.text('Add address'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a private IPv4 address, such as 192.168.1.20.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField).first, '192.168.1.20');
      await tester.tap(find.text('Add address'));
      await tester.pumpAndSettle();
      expect(find.text('192.168.1.20:45833'), findsOneWidget);
      expect(find.text('Unverified - not contacted'), findsOneWidget);
      expect(port.starts, 0);
      await tester.ensureVisible(find.byTooltip('Remove 192.168.1.20:45833'));
      await tester.tap(find.byTooltip('Remove 192.168.1.20:45833'));
      await tester.pump();
      expect(find.text('192.168.1.20:45833'), findsNothing);
    },
  );

  for (final size in [
    const Size(375, 812),
    const Size(812, 375),
    const Size(768, 1024),
    const Size(1440, 900),
  ]) {
    testWidgets('responsive navigation and planned pages at $size', (
      tester,
    ) async {
      final port = TestDiscovery();
      await launch(tester, port, size);
      if (find.byTooltip('Open navigation menu').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Send').first);
      await tester.pumpAndSettle();
      expect(find.text('Planned feature'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('native core setup error is visible instead of fake peers', (
    tester,
  ) async {
    final port = TestDiscovery()
      ..value = const DiscoverySnapshot(
        status: DiscoveryStatus.unavailable,
        message: 'Core unavailable',
      );
    await launch(tester, port, const Size(375, 812));
    expect(find.text('Native core setup needed'), findsOneWidget);
    expect(find.text('Core unavailable'), findsOneWidget);
  });

  testWidgets('settings switches light and dark appearance', (tester) async {
    await launch(tester, TestDiscovery(), const Size(1280, 800));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<ThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();
    final textContext = tester.element(find.text('Make yourself at home'));
    expect(Theme.of(textContext).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
  });
  testWidgets('visibility requires explicit name consent and can be hidden', (
    tester,
  ) async {
    final port = TestDiscovery();
    await launch(tester, port, const Size(1280, 800));
    expect(find.text('Hidden from discovery'), findsOneWidget);
    await tester.tap(find.text('Make discoverable'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.text('Show for 2 minutes'));
    await tester.pumpAndSettle();
    expect(
      find.text('Use a shorter name without control characters.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextFormField), 'Office laptop');
    await tester.tap(find.text('Show for 2 minutes'));
    await tester.pumpAndSettle();
    expect(find.text('Visible as Office laptop'), findsOneWidget);
    await tester.tap(find.text('Hide now'));
    await tester.pumpAndSettle();
    expect(find.text('Hidden from discovery'), findsOneWidget);
    expect(port.starts, 0);
  });
  testWidgets('cancelling visibility consent keeps the app hidden', (
    tester,
  ) async {
    final port = TestDiscovery();
    await launch(tester, port, const Size(1280, 800));
    await tester.tap(find.text('Make discoverable'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(port.snapshot.presence.status, PresenceStatus.hidden);
  });
  testWidgets('going to background stops scan and visibility', (tester) async {
    final port = TestDiscovery();
    await launch(tester, port, const Size(1280, 800));
    await port.makeDiscoverable('Office');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(port.snapshot.presence.status, PresenceStatus.hidden);
    expect(port.stops, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
