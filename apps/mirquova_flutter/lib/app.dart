import 'package:flutter/material.dart';

import 'core/discovery_port.dart';
import 'features/nearby/nearby_page.dart';
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
  const MirquovaApp({super.key, required this.discovery});
  final DiscoveryPort discovery;
  @override
  State<MirquovaApp> createState() => _MirquovaAppState();
}

class _MirquovaAppState extends State<MirquovaApp> with WidgetsBindingObserver {
  ThemeMode _theme = ThemeMode.system;
  int _selected = 0;
  final _manualEndpoints = <ManualEndpoint>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.discovery.stop();
      widget.discovery.hide();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.discovery.dispose();
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
    6 => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Make yourself at home',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        DropdownButtonFormField<ThemeMode>(
          initialValue: _theme,
          decoration: const InputDecoration(labelText: 'Appearance'),
          items: ThemeMode.values
              .map(
                (mode) => DropdownMenuItem(
                  value: mode,
                  child: Text(switch (mode) {
                    ThemeMode.system => 'Follow system',
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark',
                  }),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _theme = value);
            }
          },
        ),
        const SizedBox(height: 24),
        const Text(
          'Local by default. No account, cloud connection, or online subtitle requests are used in this build.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Manual addresses and appearance stay in memory for this session. Pairing and trusted-device storage are not available yet.',
        ),
      ],
    ),
    _ => _PlannedPage(index: _selected),
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
            title: const Text('Mirquova'),
            actions: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(child: Text('Preview 03')),
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
  const _PlannedPage({required this.index});
  final int index;
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
      ],
    );
  }
}
