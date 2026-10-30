enum AppSection {
  home,
  transfer,
  cast,
  player,
  devices,
  pair,
  remote,
  settings,
}

extension AppSectionLabel on AppSection {
  String get label => switch (this) {
    AppSection.home => 'Home',
    AppSection.transfer => 'Transfer',
    AppSection.cast => 'Cast',
    AppSection.player => 'Media Player',
    AppSection.devices => 'Devices',
    AppSection.pair => 'Pair',
    AppSection.remote => 'TV remote',
    AppSection.settings => 'Settings',
  };
}
