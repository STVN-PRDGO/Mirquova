import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mirquova/adapters/native_app_platform.dart';
import 'package:mirquova/adapters/package_updates.dart';
import 'package:mirquova/core/app_updates.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android update staging rejects invalid packages before installer handoff',
    (tester) async {
      const app = NativeAppPlatform();
      final info = await app.readBuildInfo();
      expect(
        AppVersion.parse(info.version, buildNumber: info.buildNumber).build,
        isNotNull,
      );
      final platform = NativePackagePlatform();
      expect(platform.packageName, 'Mirquova-preview-android-arm64-debug.apk');
      final root = await platform.updateDirectory();
      expect(await root.exists(), isTrue);
      final staging = await root.createTemp('download-native-probe-');
      try {
        // A checksum-correct download is not proof of an installable APK.
        // This deliberately invalid fixture must never reach an installer.
        final invalid = File('${staging.path}/${platform.packageName}');
        await invalid.writeAsString('Offline fixture, not an Android package.');
        await expectLater(
          platform.openPackage(invalid),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'incompatible_package',
            ),
          ),
        );
        debugPrint('[native-update-smoke] invalid APK rejected');

        final wrongName = File('${staging.path}/unapproved.apk');
        await wrongName.writeAsString('Offline fixture.');
        for (final file in [
          wrongName,
          File(
            '${staging.path}/../${staging.uri.pathSegments.where((part) => part.isNotEmpty).last}/${platform.packageName}',
          ),
          File('${staging.path}/missing/${platform.packageName}'),
        ]) {
          await expectLater(
            platform.openPackage(file),
            throwsA(
              isA<PlatformException>().having(
                (error) => error.code,
                'code',
                'invalid_package',
              ),
            ),
          );
        }
        debugPrint('[native-update-smoke] filename and path boundaries passed');
      } finally {
        await staging.delete(recursive: true);
      }
    },
    skip: !Platform.isAndroid || NativePackagePlatform().packageName == null,
  );
}
