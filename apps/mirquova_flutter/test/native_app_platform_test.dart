import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/adapters/native_app_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.mirquova/app');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final platform = NativeAppPlatform();

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'reads the installed package metadata from the native channel',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getBuildInfo');
        expect(call.arguments, isNull);
        return {'version': '1.4.0-rc.2', 'buildNumber': '230'};
      });

      final info = await platform.readBuildInfo();
      expect(info.version, '1.4.0-rc.2');
      expect(info.buildNumber, '230');
    },
  );

  test('rejects missing or malformed installed version metadata', () async {
    for (final value in <Object?>[
      null,
      'not metadata',
      {},
      {'version': '', 'buildNumber': '2'},
      {'version': 2, 'buildNumber': '2'},
      {'version': '0.2.0', 'buildNumber': 2},
      {'version': '0.2.0', 'buildNumber': '-2'},
      {'version': '0.2.0', 'buildNumber': '2.0'},
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => value);
      await expectLater(
        platform.readBuildInfo(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'version_unavailable',
          ),
        ),
      );
    }
  });

  test('opens a specific Mirquova release page through the channel', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'openReleasePage');
      expect(
        call.arguments,
        'https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0+3',
      );
      return null;
    });

    await platform.openReleasePage(
      Uri.parse('https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0+3'),
    );
  });

  test('rejects unsafe destinations before calling the native channel', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    for (final value in [
      'http://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0',
      'https://github.com.evil.test/STVN-PRDGO/Mirquova/releases/tag/v0.3.0',
      'https://user@github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0',
      'https://github.com:444/STVN-PRDGO/Mirquova/releases/tag/v0.3.0',
      'https://github.com/STVN-PRDGO/Other/releases/tag/v0.3.0',
      'https://github.com/STVN-PRDGO/Mirquova/releases',
      'https://github.com/STVN-PRDGO/Mirquova/releases/download/v0.3.0/app.exe',
      'https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0?next=evil',
      'https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0#fragment',
      'https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0%2Fevil',
      'file:///C:/app.exe',
      'https://github.com/STVN-PRDGO/Mirquova/releases/tag/${'v' * 129}',
    ]) {
      await expectLater(
        platform.openReleasePage(Uri.parse(value)),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'invalid_release_url',
          ),
        ),
      );
    }
    expect(calls, 0);
  });

  test('reports unsupported native channels as platform errors', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw MissingPluginException();
    });
    await expectLater(
      platform.readBuildInfo(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'unsupported_platform',
        ),
      ),
    );
  });

  test('preserves a native browser failure for the update UI', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'browser_unavailable');
    });
    await expectLater(
      platform.openReleasePage(
        Uri.parse('https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0'),
      ),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'browser_unavailable',
        ),
      ),
    );
  });
}
