import 'dart:io';

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
  setUpAll(() async {
    final sdk = Platform.environment['FLUTTER_ROOT'];
    if (sdk == null) {
      throw StateError('FLUTTER_ROOT is needed to load SDK fonts for previews');
    }
    final fonts = '$sdk/bin/cache/artifacts/material_fonts';
    final roboto = FontLoader('Roboto')
      ..addFont(
        File('$fonts/roboto-regular.ttf')
            .readAsBytes()
            .then(ByteData.sublistView),
      )
      ..addFont(
        File('$fonts/roboto-bold.ttf').readAsBytes().then(ByteData.sublistView),
      );
    await roboto.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File('$fonts/materialicons-regular.otf')
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
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MirquovaApp(discovery: _IdleDiscovery()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MirquovaApp),
          matchesGoldenFile(
            'goldens/nearby_${brightness.name}_${size.width.toInt()}.png',
          ),
        );
      });
    }
  }
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
    expect(find.text('Add LAN address'), findsOneWidget);
  });
}
