/// Version metadata read from the installed application package.
class AppBuildInfo {
  const AppBuildInfo({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;
}

abstract interface class AppPlatform {
  Future<AppBuildInfo> readBuildInfo();
  Future<void> openReleasePage(Uri url);
}
