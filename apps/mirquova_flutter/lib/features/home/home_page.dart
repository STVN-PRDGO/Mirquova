import 'package:flutter/material.dart';

import '../../core/discovery_port.dart';
import '../../shell/app_section.dart';
import '../../ui/surface_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.discovery,
    required this.manualEndpoints,
    required this.onOpen,
  });

  final DiscoveryPort discovery;
  final List<ManualEndpoint> manualEndpoints;
  final ValueChanged<AppSection> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: discovery,
      builder: (context, _) {
        final snapshot = discovery.snapshot;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Greeting(presence: snapshot.presence),
            const SizedBox(height: 20),
            _QuickActions(onOpen: onOpen),
            const SizedBox(height: 20),
            if (snapshot.status == DiscoveryStatus.unavailable) ...[
              const Text(
                'Native core setup needed',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              if (snapshot.message != null) ...[
                const SizedBox(height: 8),
                Text(snapshot.message!),
              ],
              const SizedBox(height: 20),
            ],
            _DevicesPanel(
              snapshot: snapshot,
              manualEndpoints: manualEndpoints,
              onOpen: onOpen,
            ),
            const SizedBox(height: 20),
            const EmptyPanel(
              icon: Icons.history,
              title: 'Recent activity',
              message: 'No transfers, casts, or playback yet. Those actions will appear here after the features are available. Nothing on this screen is a completed transfer.',
            ),
          ],
        );
      },
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.presence});

  final PresenceState presence;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hour = DateTime.now().hour;
    final hello = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final visibility = switch (presence.status) {
      PresenceStatus.hidden => 'This device is hidden',
      PresenceStatus.starting => 'Starting LAN visibility',
      PresenceStatus.visible => 'Visible on this LAN',
      PresenceStatus.stopping => 'Hiding this device',
      PresenceStatus.error => 'LAN visibility unavailable',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outline),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer,
            colors.surfaceContainerLowest,
            colors.tertiaryContainer,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hello, style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 8),
          Text(
            'Connect, send, and enjoy your media — all in one place.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 14),
          StatusChip(
            label: visibility,
            color: presence.status == PresenceStatus.visible
                ? colors.secondary
                : colors.onSurfaceVariant,
            icon: presence.status == PresenceStatus.visible
                ? Icons.wifi_tethering
                : Icons.wifi_tethering_off,
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onOpen});

  final ValueChanged<AppSection> onOpen;

  @override
  Widget build(BuildContext context) {
    const actions = <_Action>[
      _Action(
        title: 'File Transfer',
        subtitle: 'Send and receive files across your devices',
        icon: Icons.drive_folder_upload_outlined,
        colors: [Color(0xFF3B6CF6), Color(0xFF6D5EF6)],
        section: AppSection.transfer,
      ),
      _Action(
        title: 'Screen Cast',
        subtitle: 'Mirror or stream your screen',
        icon: Icons.cast_outlined,
        colors: [Color(0xFF129E96), Color(0xFF3DDC97)],
        section: AppSection.cast,
      ),
      _Action(
        title: 'Media Player',
        subtitle: 'Play your videos, music, and more',
        icon: Icons.play_arrow_rounded,
        colors: [Color(0xFFB14CFF), Color(0xFFE254C4)],
        section: AppSection.player,
      ),
      _Action(
        title: 'OpenSubtitles',
        subtitle: 'Search and download subtitles online',
        icon: Icons.subtitles_outlined,
        colors: [Color(0xFFF08A2C), Color(0xFFFFB020)],
        section: AppSection.player,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        const gap = 14.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final action in actions)
              SizedBox(
                width: width,
                child: _ActionCard(action: action, onOpen: onOpen),
              ),
          ],
        );
      },
    );
  }
}

class _Action {
  const _Action({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.section,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final AppSection section;
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action, required this.onOpen});

  final _Action action;
  final ValueChanged<AppSection> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => onOpen(action.section),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 112),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(colors: action.colors),
                  ),
                  child: Icon(action.icon, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        action.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(action.subtitle),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DevicesPanel extends StatelessWidget {
  const _DevicesPanel({
    required this.snapshot,
    required this.manualEndpoints,
    required this.onOpen,
  });

  final DiscoverySnapshot snapshot;
  final List<ManualEndpoint> manualEndpoints;
  final ValueChanged<AppSection> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final empty = snapshot.peers.isEmpty && manualEndpoints.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Nearby devices', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text(
          'Names from discovery are claims, not connected or trusted devices.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => onOpen(AppSection.devices),
              child: const Text('Devices'),
            ),
            TextButton(
              onPressed: () => onOpen(AppSection.pair),
              child: const Text('Pair'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (empty)
          const EmptyPanel(
            icon: Icons.radar_outlined,
            title: 'No devices found',
            message: 'Scan from Devices on the same LAN. A saved address is kept for this session only and is not contacted.',
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 800 ? 2 : 1;
              const gap = 12.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final peer in snapshot.peers)
                    SizedBox(
                      width: width,
                      child: SurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              peer.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            const StatusChip(
                              label: 'Unverified',
                              color: Color(0xFFF5B84B),
                              icon: Icons.help_outline,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Seen in the last scan. Not paired and not a confirmed receiver.',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  for (final endpoint in manualEndpoints)
                    SizedBox(
                      width: width,
                      child: SurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              endpoint.key,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            const StatusChip(
                              label: 'Not contacted',
                              color: Color(0xFF71819A),
                              icon: Icons.link_off,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}
