import 'package:flutter/material.dart';

import '../../adapters/native_cast.dart';
import '../../adapters/native_transfer.dart';
import '../../core/discovery_port.dart';
import '../../core/playback.dart';
import '../../core/transfer_state.dart';
import '../../shell/app_section.dart';
import '../../ui/surface_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.discovery,
    required this.manualEndpoints,
    required this.onOpen,
    this.transfer,
    this.cast,
    this.playback,
  });

  final DiscoveryPort discovery;
  final List<ManualEndpoint> manualEndpoints;
  final ValueChanged<AppSection> onOpen;
  final TransferService? transfer;
  final CastService? cast;
  final LocalPlayback? playback;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([discovery, ?transfer, ?cast, ?playback]),
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
            _SessionPanel(
              transfer: transfer,
              cast: cast,
              playback: playback,
              onOpen: onOpen,
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

class _SessionPanel extends StatelessWidget {
  const _SessionPanel({
    required this.transfer,
    required this.cast,
    required this.playback,
    required this.onOpen,
  });

  final TransferService? transfer;
  final CastService? cast;
  final LocalPlayback? playback;
  final ValueChanged<AppSection> onOpen;

  @override
  Widget build(BuildContext context) {
    final rows = <_SessionRow>[_transferRow(), _castRow(), _playerRow()];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Right now', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text(
          'This is the current session. A discovered name is still not a paired device.',
        ),
        const SizedBox(height: 12),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              for (final row in rows)
                ListTile(
                  leading: Icon(row.icon, color: row.color),
                  title: Text(row.title),
                  subtitle: Text(row.detail),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onOpen(row.section),
                ),
            ],
          ),
        ),
      ],
    );
  }

  _SessionRow _transferRow() {
    final service = transfer;
    if (service == null) {
      return const _SessionRow(
        icon: Icons.drive_folder_upload_outlined,
        title: 'File transfer',
        detail: 'The native core is not available in this build.',
        section: AppSection.transfer,
      );
    }
    if (service.incomingNeedsAnswer) {
      final sender = service.incomingPeer?.alias ?? 'A paired device';
      return _SessionRow(
        icon: Icons.download_outlined,
        title: 'File waiting',
        detail:
            '$sender is asking to send a file. Accept or decline on the prompt.',
        section: AppSection.transfer,
        color: const Color(0xFFF5B84B),
      );
    }
    if (service.incoming.status == TransferStatus.transferring) {
      return _SessionRow(
        icon: Icons.download_outlined,
        title: 'Receiving',
        detail:
            '${formatBytes(service.incoming.transferredBytes)} of ${formatBytes(service.incoming.totalBytes)}',
        section: AppSection.transfer,
        color: const Color(0xFF22D3EE),
      );
    }
    if (service.sending) {
      final alias = service.outgoingPeer?.alias ?? 'a paired device';
      final snapshot = service.outgoing;
      final detail = snapshot.status == TransferStatus.transferring
          ? 'Sending to $alias · ${formatBytes(snapshot.transferredBytes)} of ${formatBytes(snapshot.totalBytes)}'
          : 'Sending to $alias';
      return _SessionRow(
        icon: Icons.upload_outlined,
        title: 'Sending',
        detail: detail,
        section: AppSection.transfer,
        color: const Color(0xFF3478F6),
      );
    }
    final problem = service.receiveProblem;
    if (problem != null) {
      return _SessionRow(
        icon: Icons.error_outline,
        title: 'Receive paused',
        detail: problem,
        section: AppSection.transfer,
        color: const Color(0xFFF16B78),
      );
    }
    if (service.peers.isEmpty) {
      return const _SessionRow(
        icon: Icons.drive_folder_upload_outlined,
        title: 'File transfer',
        detail: 'Pair a device once. Files are saved only after the other device accepts.',
        section: AppSection.transfer,
      );
    }
    return _SessionRow(
      icon: Icons.drive_folder_upload_outlined,
      title: 'Ready to send and receive',
      detail: service.receiving
          ? '${service.peers.length} paired ${service.peers.length == 1 ? 'device' : 'devices'}. Choose files, then tap a device.'
          : 'Starting the receiver…',
      section: AppSection.transfer,
      color: const Color(0xFF22C98A),
    );
  }

  _SessionRow _castRow() {
    final service = cast;
    if (service == null) {
      return const _SessionRow(
        icon: Icons.cast_outlined,
        title: 'Screen share',
        detail: 'The native core is not available in this build.',
        section: AppSection.cast,
      );
    }
    if (service.incomingNeedsAnswer) {
      final sender = service.incomingPeer?.alias ?? 'A paired device';
      return _SessionRow(
        icon: Icons.cast_connected,
        title: 'Screen share waiting',
        detail:
            '$sender wants to share its screen. Accept or decline on the prompt.',
        section: AppSection.cast,
        color: const Color(0xFFF5B84B),
      );
    }
    if (service.incomingLive) {
      final sender = service.incomingPeer?.alias ?? 'A paired device';
      return _SessionRow(
        icon: Icons.cast_connected,
        title: 'Watching a screen',
        detail: 'Live share from $sender.',
        section: AppSection.cast,
        color: const Color(0xFF22D3EE),
      );
    }
    if (service.sending) {
      final alias = service.outgoingPeer?.alias ?? 'a paired device';
      final size = service.outgoing.width == null
          ? ''
          : ' · ${service.outgoing.width}×${service.outgoing.height}';
      return _SessionRow(
        icon: Icons.cast_connected,
        title: 'Sharing this screen',
        detail:
            'To $alias$size${service.outgoing.audio ? ' with system audio' : ''}',
        section: AppSection.cast,
        color: const Color(0xFF8B5CF6),
      );
    }
    if (!service.captureSupported) {
      return const _SessionRow(
        icon: Icons.cast_outlined,
        title: 'Can receive a screen',
        detail: 'This device cannot capture its own screen. A paired Windows or Android device can share here.',
        section: AppSection.cast,
      );
    }
    if (service.peers.isEmpty) {
      return const _SessionRow(
        icon: Icons.cast_outlined,
        title: 'Screen share',
        detail: 'Pair a device, then tap it. The other device accepts before anything is shown.',
        section: AppSection.cast,
      );
    }
    return _SessionRow(
      icon: Icons.cast_outlined,
      title: 'Ready to share this screen',
      detail:
          '${service.peers.length} paired ${service.peers.length == 1 ? 'device' : 'devices'}. This is Mirquova screen share, not Chromecast.',
      section: AppSection.cast,
      color: const Color(0xFF22C98A),
    );
  }

  _SessionRow _playerRow() {
    final media = playback;
    if (media == null || media.name == null) {
      return const _SessionRow(
        icon: Icons.play_arrow_rounded,
        title: 'Media player',
        detail: 'Open a file on this device. Space plays and pauses.',
        section: AppSection.player,
      );
    }
    if (media.error != null) {
      return _SessionRow(
        icon: Icons.play_disabled_outlined,
        title: media.name ?? 'Media',
        detail: media.error!,
        section: AppSection.player,
        color: const Color(0xFFF16B78),
      );
    }
    return _SessionRow(
      icon: media.playing
          ? Icons.pause_circle_outline
          : Icons.play_arrow_rounded,
      title: media.name ?? 'Media',
      detail: media.playing
          ? 'Playing on this device'
          : 'Paused on this device',
      section: AppSection.player,
      color: const Color(0xFF8B5CF6),
    );
  }
}

class _SessionRow {
  const _SessionRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.section,
    this.color,
  });

  final IconData icon;
  final String title;
  final String detail;
  final AppSection section;
  final Color? color;
}
