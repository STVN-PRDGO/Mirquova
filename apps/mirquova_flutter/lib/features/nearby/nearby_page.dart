import 'package:flutter/material.dart';

import '../../core/discovery_port.dart';

class NearbyPage extends StatelessWidget {
  const NearbyPage({
    super.key,
    required this.discovery,
    required this.manualEndpoints,
    required this.onAdd,
    required this.onRemove,
  });
  final DiscoveryPort discovery;
  final List<ManualEndpoint> manualEndpoints;
  final ValueChanged<ManualEndpoint> onAdd;
  final ValueChanged<ManualEndpoint> onRemove;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: discovery,
    builder: (context, _) {
      final snapshot = discovery.snapshot;
      final scanning = snapshot.status == DiscoveryStatus.scanning;
      final available = snapshot.status != DiscoveryStatus.unavailable;
      final colors = Theme.of(context).colorScheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      Icons.wifi_tethering,
                      color: colors.onPrimaryContainer,
                    ),
                    Text(
                      'YOUR LOCAL NETWORK',
                      style: TextStyle(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Your devices, closer.',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Find Mirquova devices on your local network. You decide what connects and what gets shared.',
                  style: TextStyle(
                    color: colors.onPrimaryContainer,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    _NetworkFact(
                      icon: Icons.devices_outlined,
                      label: '${snapshot.peers.length} discovered',
                    ),
                    _NetworkFact(
                      icon: Icons.link_outlined,
                      label: '${manualEndpoints.length} saved addresses',
                    ),
                    const _NetworkFact(
                      icon: Icons.shield_outlined,
                      label: 'Permission first',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: scanning || !available ? null : discovery.start,
                icon: const Icon(Icons.radar_outlined),
                label: const Text('Scan nearby'),
              ),
              if (scanning)
                OutlinedButton.icon(
                  onPressed: discovery.stop,
                  icon: const Icon(Icons.stop_outlined),
                  label: const Text('Stop scan'),
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  final endpoint = await showDialog<ManualEndpoint>(
                    context: context,
                    builder: (_) => const _AddressDialog(),
                  );
                  if (endpoint != null && context.mounted) {
                    final duplicate = manualEndpoints.any(
                      (item) => item.key == endpoint.key,
                    );
                    if (!duplicate) onAdd(endpoint);
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            duplicate
                                ? 'This address is already saved.'
                                : 'Address saved for this session.',
                          ),
                        ),
                      );
                  }
                },
                icon: const Icon(Icons.add_link_outlined),
                label: const Text('Add LAN address'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    snapshot.presence.active
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(switch (snapshot.presence.status) {
                      PresenceStatus.hidden => 'Hidden from discovery',
                      PresenceStatus.starting => 'Starting LAN visibility',
                      PresenceStatus.visible =>
                        'Visible as ${snapshot.presence.alias}',
                      PresenceStatus.stopping => 'Hiding this device',
                      PresenceStatus.error => 'LAN visibility unavailable',
                    }, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Share a chosen name with devices on this LAN for up to two minutes. This does not allow connections or file access.',
                  ),
                  if (snapshot.presence.status == PresenceStatus.visible) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Hides automatically in ${snapshot.presence.remainingSeconds ~/ 60}:${(snapshot.presence.remainingSeconds % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (snapshot.presence.message != null) ...[
                    const SizedBox(height: 8),
                    Text(snapshot.presence.message!),
                  ],
                  const SizedBox(height: 16),
                  if (snapshot.presence.active)
                    OutlinedButton.icon(
                      onPressed:
                          snapshot.presence.status == PresenceStatus.stopping
                          ? null
                          : discovery.hide,
                      icon: const Icon(Icons.visibility_off_outlined),
                      label: const Text('Hide now'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: !available
                          ? null
                          : () async {
                              final alias = await showDialog<String>(
                                context: context,
                                builder: (_) => const _VisibilityDialog(),
                              );
                              if (alias != null && context.mounted) {
                                await discovery.makeDiscoverable(alias);
                              }
                            },
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Make discoverable'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          Semantics(
            liveRegion: true,
            child: Text(switch (snapshot.status) {
              DiscoveryStatus.idle => 'Ready when you are',
              DiscoveryStatus.scanning => 'Scanning your LAN for 6 seconds...',
              DiscoveryStatus.complete => 'Scan complete',
              DiscoveryStatus.stopped => 'Scan stopped',
              DiscoveryStatus.error => 'Scan interrupted',
              DiscoveryStatus.unavailable => 'Native core setup needed',
            }, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 12),
          if (snapshot.message != null) ...[
            Text(snapshot.message!),
            const SizedBox(height: 16),
          ],
          if (scanning) ...[
            LinearProgressIndicator(
              value: MediaQuery.disableAnimationsOf(context) ? 0.5 : null,
              semanticsLabel: 'Scanning the local network',
            ),
            const SizedBox(height: 24),
          ],
          if (snapshot.peers.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.radar_outlined,
                      size: 40,
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    scanning
                        ? 'Looking for nearby devices'
                        : 'No devices listed yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'On the other device, choose Make discoverable, then scan here on the same LAN. If multicast is blocked, you can save its LAN address below for a later connection.',
                  ),
                ],
              ),
            ),
          for (final peer in snapshot.peers)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        peer.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      SelectableText(peer.addresses.join(', ')),
                      const SizedBox(height: 8),
                      const Text(
                        'Unverified - seen in the last scan. Pairing is not available yet.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 32),
          Text(
            'Manual addresses',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Private IPv4 addresses only in this preview. Adding an address saves it for this session; it does not contact, pair, or trust the device.',
          ),
          if (manualEndpoints.isEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'No saved addresses. Use Add LAN address to keep one here.',
            ),
          ],
          for (final endpoint in manualEndpoints)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(
                child: ListTile(
                  title: Text(endpoint.key),
                  subtitle: const Text('Unverified - not contacted'),
                  trailing: IconButton(
                    tooltip: 'Remove ${endpoint.key}',
                    onPressed: () => onRemove(endpoint),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 32),
          const Text(
            'Built around your permission',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Discovery names are claims, not verified identities, and cannot start pairing or a transfer. Pair first, then send files to that trusted device. Playback opens local files. Screen capture is not included.',
          ),
        ],
      );
    },
  );
}

class _NetworkFact extends StatelessWidget {
  const _NetworkFact({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 18,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    ],
  );
}

class _AddressDialog extends StatefulWidget {
  const _AddressDialog();
  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final _form = GlobalKey<FormState>();
  final _address = TextEditingController();
  final _port = TextEditingController(text: '45833');
  @override
  void dispose() {
    _address.dispose();
    _port.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, ManualEndpoint.parse(_address.text, _port.text));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a LAN address'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _address,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Private IPv4 address',
                hintText: '192.168.1.20',
              ),
              validator: (_) =>
                  ManualEndpoint.parse(_address.text, '45833') == null
                  ? 'Enter a private IPv4 address, such as 192.168.1.20.'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _port,
              keyboardType: TextInputType.number,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'Port'),
              validator: (_) =>
                  ManualEndpoint.parse('192.168.1.1', _port.text) == null
                  ? 'Enter a port from 1 to 65535.'
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Add address')),
    ],
  );
}

class _VisibilityDialog extends StatefulWidget {
  const _VisibilityDialog();
  @override
  State<_VisibilityDialog> createState() => _VisibilityDialogState();
}

class _VisibilityDialogState extends State<_VisibilityDialog> {
  final _form = GlobalKey<FormState>();
  final _alias = TextEditingController(text: 'Mirquova device');
  @override
  void dispose() {
    _alias.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _alias.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose your visible name'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Devices on this LAN can see this name and your local address. Visibility expires after two minutes and stops when the app is hidden or closed.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _alias,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Visible name'),
              onFieldSubmitted: (_) => _submit(),
              validator: (_) => PresenceState.validAlias(_alias.text)
                  ? null
                  : 'Use a shorter name without control characters.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Show for 2 minutes')),
    ],
  );
}
