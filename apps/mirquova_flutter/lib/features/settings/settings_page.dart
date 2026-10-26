import 'package:flutter/material.dart';

import '../../core/app_platform.dart';
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
    required this.appPlatform,
  });

  final ThemeMode theme;
  final ValueChanged<ThemeMode> onThemeChanged;
  final UpdateController? updates;
  final bool readingVersion;
  final VoidCallback onRetryVersion;
  final AppPlatform appPlatform;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Make yourself at home',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 24),
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
        appPlatform: appPlatform,
      ),
      const SizedBox(height: 24),
      const Text(
        'Local by default. Update checks contact GitHub only with your permission. No account or online subtitle requests are used in this build.',
      ),
      const SizedBox(height: 16),
      const Text(
        'Manual addresses, appearance, and update results stay in memory for this session. Pairing and trusted-device storage are not available yet.',
      ),
    ],
  );
}
