import 'dart:async';

import 'package:flutter/material.dart';

import 'adapters/github_updates.dart';
import 'adapters/package_updates.dart';
import 'adapters/native_app_platform.dart';
import 'core/app_platform.dart';
import 'core/app_updates.dart';
import 'core/discovery_port.dart';
import 'features/nearby/nearby_page.dart';
import 'features/settings/settings_page.dart';
import 'theme.dart';

const destinations = <(String, IconData)>[
  ('Nearby', Icons.radar_outlined),
  ('Send', Icons.upload_file_outlined),
  ('Receive', Icons.download_outlined),
  ('Cast', Icons.cast_outlined),
  ('Media Library', Icons.video_library_outlined),
  ('Activity', Icons.history_outlined),
  ('Settings', Icons.settings_outlined),
];

class MirquovaApp extends StatefulWidget {
  const MirquovaApp({
    super.key,
    required this.discovery,
    this.appPlatform = const NativeAppPlatform(),
    this.updateSource,
    this.packageUpdates,
  });
  final DiscoveryPort discovery;
  final AppPlatform appPlatform;
  final UpdateSource? updateSource;
  final PackageUpdates? packageUpdates;
  @override
  State<MirquovaApp> createState() => _MirquovaAppState();
}

class _MirquovaAppState extends State<MirquovaApp> with WidgetsBindingObserver {
  ThemeMode _theme = ThemeMode.system;
  int _selected = 0;
  final _manualEndpoints = <ManualEndpoint>[];
  UpdateController? _updates;
  bool _readingVersion = true;
  late final PackageUpdates _packages;

  @override
  void initState() {
    super.initState();
    _packages = widget.packageUpdates ?? PackageUpdates();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadInstalledVersion());
  }

  Future<void> _loadInstalledVersion() async {
    setState(() => _readingVersion = true);
    UpdateController? updates;
    try {
      final info = await widget.appPlatform.readBuildInfo();
      updates = UpdateController(
        currentVersion: AppVersion.parse(
          info.version,
          buildNumber: info.buildNumber,
        ),
        source: widget.updateSource ?? GitHubUpdateSource(),
      );
    } on Exception {
      // An unknown installed version must never be treated as an older build.
    }
    if (!mounted) {
      updates?.dispose();
      return;
    }
    setState(() {
      _updates?.dispose();
      _updates = updates;
      _readingVersion = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.discovery.stop();
      widget.discovery.hide();
      _updates?.cancel();
      _packages.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.discovery.dispose();
    _updates?.dispose();
    _packages.dispose();
    super.dispose();
  }

  Widget _page() => switch (_selected) {
    0 => NearbyPage(
      discovery: widget.discovery,
      manualEndpoints: _manualEndpoints,
      onAdd: (endpoint) => setState(() {
        if (!_manualEndpoints.any((item) => item.key == endpoint.key)) {
          _manualEndpoints.add(endpoint);
        }
      }),
      onRemove: (endpoint) => setState(() => _manualEndpoints.remove(endpoint)),
    ),
    6 => SettingsPage(
      theme: _theme,
      onThemeChanged: (value) => setState(() => _theme = value),
      updates: _updates,
      readingVersion: _readingVersion,
      onRetryVersion: _loadInstalledVersion,
      packages: _packages,
    ),
    _ => _PlannedPage(
      index: _selected,
      onNearby: () => setState(() => _selected = 0),
    ),
  };

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mirquova',
    debugShowCheckedModeBanner: false,
    theme: mirquovaTheme(Brightness.light),
    darkTheme: mirquovaTheme(Brightness.dark),
    themeMode: _theme,
    home: LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 1000 &&
            constraints.maxHeight >= 640 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.4;
        final medium =
            constraints.maxWidth >= 700 &&
            constraints.maxHeight >= 640 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.4;
        return Scaffold(
          appBar: AppBar(
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hub_outlined),
                SizedBox(width: 10),
                Flexible(child: Text('Mirquova')),
              ],
            ),
            actions: [
              if (medium)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: Chip(
                      avatar: Icon(Icons.science_outlined, size: 16),
                      label: Text('Preview 04'),
                      side: BorderSide.none,
                    ),
                  ),
                ),
            ],
          ),
          drawer: medium
              ? null
              : Drawer(
                  child: SafeArea(
                    child: ListView(
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Every screen. One connection.',
                            style: TextStyle(fontSize: 20),
                          ),
                        ),
                        ...List.generate(
                          destinations.length,
                          (index) => ListTile(
                            leading: Icon(destinations[index].$2),
                            title: Text(destinations[index].$1),
                            selected: _selected == index,
                            onTap: () {
                              setState(() => _selected = index);
                              Navigator.pop(context);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (medium) ...[
                  NavigationRail(
                    minExtendedWidth: 216,
                    leading: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Icon(Icons.sensors, size: 32),
                    ),
                    extended: wide,
                    selectedIndex: _selected,
                    labelType: wide
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,
                    onDestinationSelected: (value) =>
                        setState(() => _selected = value),
                    destinations: destinations
                        .map(
                          (item) => NavigationRailDestination(
                            icon: Icon(item.$2),
                            label: Text(item.$1),
                          ),
                        )
                        .toList(),
                  ),
                  const VerticalDivider(width: 1),
                ],
                Expanded(
                  child: SingleChildScrollView(
                    key: ValueKey(_selected),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1080),
                        child: Padding(
                          padding: EdgeInsets.all(medium ? 32 : 20),
                          child: _page(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _PlannedPage extends StatelessWidget {
  const _PlannedPage({required this.index, required this.onNearby});
  final int index;
  final VoidCallback onNearby;
  @override
  Widget build(BuildContext context) {
    final descriptions = <int, String>{
      1: 'Choose files and send them after device verification and transfer consent are implemented.',
      2: 'Incoming files will require your approval. This preview does not accept files or open a transfer server.',
      3: 'App-to-app screen casting will use native capture permissions and a visible stop control.',
      4: 'Local playback and offline captions are planned after the connection foundation.',
      5: 'Verified transfer and casting activity will appear here once those features are available.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          destinations[index].$2,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          destinations[index].$1,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'Planned feature',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(descriptions[index]!),
        const SizedBox(height: 28),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.route_outlined),
                const SizedBox(height: 16),
                Text(
                  'Start with discovery',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'You can scan your LAN, make this device temporarily visible, and save manual addresses. Secure pairing is the next milestone before sharing becomes available.',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onNearby,
                  icon: const Icon(Icons.radar_outlined),
                  label: const Text('Go to Nearby'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
