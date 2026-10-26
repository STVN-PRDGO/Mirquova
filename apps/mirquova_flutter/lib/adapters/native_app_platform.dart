import 'package:flutter/services.dart';

import '../core/app_platform.dart';

class NativeAppPlatform implements AppPlatform {
  const NativeAppPlatform();

  static const _channel = MethodChannel('dev.mirquova/app');
  static final _releasePage = RegExp(
    r'^https://github\.com/STVN-PRDGO/Mirquova/releases/tag/[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$',
  );

  @override
  Future<AppBuildInfo> readBuildInfo() async {
    final result = await _invoke<Object>('getBuildInfo');
    final version = result is Map ? result['version'] : null;
    final buildNumber = result is Map ? result['buildNumber'] : null;
    if (version is! String ||
        version.isEmpty ||
        version.length > 128 ||
        buildNumber is! String ||
        !RegExp(r'^[0-9]{1,20}$').hasMatch(buildNumber)) {
      throw PlatformException(
        code: 'version_unavailable',
        message: 'The installed application version could not be read.',
      );
    }
    return AppBuildInfo(version: version, buildNumber: buildNumber);
  }

  @override
  Future<void> openReleasePage(Uri url) async {
    final value = url.toString();
    if (!_releasePage.hasMatch(value)) {
      throw PlatformException(
        code: 'invalid_release_url',
        message: 'Only Mirquova GitHub release pages can be opened.',
      );
    }
    await _invoke<void>('openReleasePage', value);
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw PlatformException(
        code: 'unsupported_platform',
        message: 'Application updates are unavailable on this platform.',
      );
    }
  }
}
