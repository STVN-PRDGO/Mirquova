import 'package:flutter/material.dart';

import '../../adapters/package_updates.dart';
import '../../core/app_updates.dart';
import 'system_updates_card.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.theme,
    required this.onThemeChanged,
    required this.updates,
    required this.readingVersion,
    required this.onRetryVersion,
    required this.packages,
    required this.onOpenDevices,
    required this.onOpenPair,
  });

  final ThemeMode theme;
  final ValueChanged<ThemeMode> onThemeChanged;
  final UpdateController? updates;
  final bool readingVersion;
  final VoidCallback onRetryVersion;
  final PackageUpdates packages;
  final VoidCallback onOpenDevices;
  final VoidCallback onOpenPair;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Settings', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 6),
      const Text('Every screen. One connection.'),
      const SizedBox(height: 24),
      Text('General', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      DropdownButtonFormField<ThemeMode>(
        initialValue: theme,
        isExpanded: true,
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
          if (value != null) onThemeChanged(value);
        },
      ),
      const SizedBox(height: 24),
      SystemUpdatesCard(
        updates: updates,
        readingVersion: readingVersion,
        onRetryVersion: onRetryVersion,
        packages: packages,
      ),
      const SizedBox(height: 24),
      const Text(
        'Local by default. Update checks contact GitHub only with your permission. No account or online subtitle requests are used in this build.',
      ),
      const SizedBox(height: 16),
      const Text(
        'Manual addresses, appearance, and update results stay in memory for this session. Pairing identities and trusted-device records use OS-backed secure storage when the platform service is available.',
      ),
      const SizedBox(height: 28),
      Text('Network', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text(
        'Discovery and saved LAN addresses stay on this device. Scanning never starts by itself.',
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: onOpenDevices,
        icon: const Icon(Icons.devices_outlined),
        label: const Text('Open devices'),
      ),
      const SizedBox(height: 28),
      Text('Security', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text(
        'Pairing uses a fingerprint you compare on both devices. Trust is not implied by a nearby name.',
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: onOpenPair,
        icon: const Icon(Icons.verified_user_outlined),
        label: const Text('Open pairing'),
      ),
      const SizedBox(height: 28),
      Text('About', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text(
        'File transfer runs between paired devices after approval. Playback opens local files. Screen capture is not included. OpenSubtitles runs only when you opt in with your own API key.',
      ),
    ],
  );
}
