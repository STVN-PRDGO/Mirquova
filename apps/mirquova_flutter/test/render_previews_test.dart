import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/app.dart';
import 'package:mirquova/core/discovery_port.dart';

class _IdleDiscovery extends DiscoveryPort {
  @override
  DiscoverySnapshot get snapshot => const DiscoverySnapshot();
  @override
  Future<void> start() async {}
  @override
  void stop() {}
  @override
  Future<void> makeDiscoverable(String alias) async {}
  @override
  void hide() {}
}

void main() {
  const profile = String.fromEnvironment(
    'MIRQUOVA_GOLDEN_PROFILE',
    defaultValue: 'local',
  );
  if (profile != 'local' && profile != 'macos-15') {
    throw ArgumentError('Unknown golden profile: $profile');
  }
  final referenceDirectory = profile == 'local'
      ? 'goldens'
      : 'goldens/$profile';
  group('SDK-font reference renders', () {
    setUpAll(() async {
      final sdk = Platform.environment['FLUTTER_ROOT'];
      if (sdk == null) {
        throw StateError(
          'FLUTTER_ROOT is needed to load SDK fonts for previews',
        );
      }
      final fonts = '$sdk/bin/cache/artifacts/material_fonts';
      final roboto = FontLoader('Roboto')
        ..addFont(
          File('$fonts/Roboto-Regular.ttf')
              .readAsBytes()
              .then(ByteData.sublistView),
        )
        ..addFont(
          File('$fonts/Roboto-Bold.ttf')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
      await roboto.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File('$fonts/MaterialIcons-Regular.otf')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
      await icons.load();
    });
    for (final brightness in Brightness.values) {
      for (final size in [const Size(375, 812), const Size(1440, 900)]) {
        testWidgets('Nearby ${brightness.name} ${size.width.toInt()}', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(size);
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(MirquovaApp(discovery: _IdleDiscovery()));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byType(MirquovaApp),
            matchesGoldenFile(
              '$referenceDirectory/nearby_${brightness.name}_${size.width.toInt()}.png',
            ),
          );
        }, tags: ['golden']);
      }
    }
  });
  testWidgets('large text and reduced motion do not overflow a small phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MirquovaApp(discovery: _IdleDiscovery()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Drawer), matching: find.text('Devices')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add LAN address'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
