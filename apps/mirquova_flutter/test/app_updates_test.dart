import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/core/app_updates.dart';

class _Source implements UpdateSource {
  int checks = 0;
  int cancellations = 0;
  Completer<UpdateRelease?> response = Completer<UpdateRelease?>();

  @override
  Future<UpdateRelease?> latest() {
    checks++;
    return response.future;
  }

  @override
  void cancel() => cancellations++;
}

UpdateRelease _release(String version) => UpdateRelease(
  version: AppVersion.parse(version),
  pageUrl: Uri.parse(
    'https://github.com/STVN-PRDGO/Mirquova/releases/tag/v$version',
  ),
);

void main() {
  test('version comparison uses numeric components and build numbers', () {
    expect(
      AppVersion.parse('v0.10.0').isNewerThan(AppVersion.parse('0.9.9')),
      isTrue,
    );
    expect(
      AppVersion.parse('0.2.0+10').isNewerThan(AppVersion.parse('0.2.0+9')),
      isTrue,
    );
    expect(
      AppVersion.parse('0.2.0+1').isNewerThan(AppVersion.parse('0.2.0+2')),
      isFalse,
    );
    expect(
      AppVersion.parse('0.1.9+999').isNewerThan(AppVersion.parse('0.2.0+2')),
      isFalse,
    );
    expect(
      AppVersion.parse('0.3.0+1').isNewerThan(AppVersion.parse('0.2.0+999')),
      isTrue,
    );
    expect(AppVersion.parse('0.2.0', buildNumber: '2').toString(), '0.2.0+2');
  });

  test('a plain tag cannot upgrade an equal known build', () {
    expect(
      AppVersion.parse('0.2.0').isNewerThan(AppVersion.parse('0.2.0+2')),
      isFalse,
    );
    expect(
      AppVersion.parse('0.2.0+3').isNewerThan(AppVersion.parse('0.2.0')),
      isFalse,
    );
  });

  test('malformed, ambiguous and prerelease versions are rejected', () {
    for (final version in [
      '',
      '0.2',
      '0.02.0',
      '0.2.0+02',
      '0.2.0-beta',
      '0.2.0+abc',
      '0.2.0\n',
      '1.0.0/other',
      '99999999999999999999.0.0',
    ]) {
      expect(() => AppVersion.parse(version), throwsFormatException);
    }
    expect(
      () => AppVersion.parse('0.2.0+2', buildNumber: '3'),
      throwsFormatException,
    );
    expect(
      () => AppVersion.parse('0.2.0', buildNumber: '-1'),
      throwsFormatException,
    );
  });

  test('controller construction performs no update request', () {
    final source = _Source();
    final controller = UpdateController(
      currentVersion: AppVersion.parse('0.2.0+2'),
      source: source,
    );
    expect(source.checks, 0);
    expect(controller.status, UpdateStatus.idle);
    expect(controller.lastChecked, isNull);
    controller.dispose();
  });

  test('check is single flight, including listener reentry', () async {
    final source = _Source();
    final controller = UpdateController(
      currentVersion: AppVersion.parse('0.2.0+2'),
      source: source,
    );
    addTearDown(controller.dispose);
    Future<void>? reentrant;
    controller.addListener(() {
      if (controller.status == UpdateStatus.checking) {
        reentrant = controller.check();
      }
    });
    final check = controller.check();
    expect(controller.status, UpdateStatus.checking);
    expect(identical(check, controller.check()), isTrue);
    expect(identical(check, reentrant), isTrue);
    expect(source.checks, 1);
    source.response.complete(_release('0.3.0'));
    await check;
    expect(controller.status, UpdateStatus.available);
    expect(controller.release?.version.toString(), '0.3.0');
    expect(controller.lastChecked, isNotNull);
  });

  for (final version in ['0.2.0', '0.2.0+1', '0.2.0+2', '0.1.0+99']) {
    test('equal or older $version never offers a downgrade', () async {
      final source = _Source()..response.complete(_release(version));
      final controller = UpdateController(
        currentVersion: AppVersion.parse('0.2.0+2'),
        source: source,
      );
      addTearDown(controller.dispose);
      await controller.check();
      expect(controller.status, UpdateStatus.upToDate);
    });
  }

  test(
    'no published release differs from an up-to-date installation',
    () async {
      final source = _Source()..response.complete(null);
      final controller = UpdateController(
        currentVersion: AppVersion.parse('0.2.0+2'),
        source: source,
      );
      addTearDown(controller.dispose);
      await controller.check();
      expect(controller.status, UpdateStatus.noRelease);
      expect(controller.release, isNull);
    },
  );

  test('cancel resolves promptly and ignores late results', () async {
    final source = _Source();
    final controller = UpdateController(
      currentVersion: AppVersion.parse('0.2.0+2'),
      source: source,
    );
    addTearDown(controller.dispose);
    final check = controller.check();
    controller.cancel();
    await check;
    expect(source.cancellations, 1);
    expect(controller.status, UpdateStatus.idle);
    source.response.complete(_release('9.0.0'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, UpdateStatus.idle);
    expect(controller.release, isNull);
    expect(controller.lastChecked, isNull);
  });

  test(
    'a fresh check after cancellation ignores the previous attempt',
    () async {
      final source = _Source();
      final controller = UpdateController(
        currentVersion: AppVersion.parse('0.2.0+2'),
        source: source,
      );
      addTearDown(controller.dispose);
      final oldResponse = source.response;
      final oldCheck = controller.check();
      controller.cancel();
      source.response = Completer<UpdateRelease?>();
      final newCheck = controller.check();
      oldResponse.complete(_release('9.0.0'));
      await oldCheck;
      expect(controller.status, UpdateStatus.checking);
      source.response.complete(_release('0.2.0+2'));
      await newCheck;
      expect(controller.status, UpdateStatus.upToDate);
      expect(source.checks, 2);
    },
  );

  test(
    'failed checks clear stale availability without leaking exceptions',
    () async {
      final source = _Source()..response.complete(_release('0.3.0'));
      final controller = UpdateController(
        currentVersion: AppVersion.parse('0.2.0+2'),
        source: source,
      );
      addTearDown(controller.dispose);
      await controller.check();
      final previousCheck = controller.lastChecked;
      source.response = Completer<UpdateRelease?>();
      final check = controller.check();
      source.response.completeError(StateError('private path and credentials'));
      await check;
      expect(controller.status, UpdateStatus.error);
      expect(controller.release, isNull);
      expect(controller.lastChecked, previousCheck);
      expect(controller.message, isNot(contains('private')));
    },
  );

  test(
    'dispose cancels a pending check and suppresses late notifications',
    () async {
      final source = _Source();
      final controller = UpdateController(
        currentVersion: AppVersion.parse('0.2.0+2'),
        source: source,
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      final check = controller.check();
      controller.dispose();
      await check;
      source.response.completeError(StateError('late failure'));
      await Future<void>.delayed(Duration.zero);
      expect(source.cancellations, 1);
      expect(notifications, 1);
      await controller.check();
      expect(source.checks, 1);
    },
  );
}
