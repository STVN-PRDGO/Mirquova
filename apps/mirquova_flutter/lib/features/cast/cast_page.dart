import 'package:flutter/material.dart';

import '../../core/discovery_port.dart';
import '../../ui/surface_card.dart';

class CastPage extends StatefulWidget {
  const CastPage({
    super.key,
    required this.discovery,
    required this.onOpenDevices,
    required this.onOpenRemote,
  });

  final DiscoveryPort discovery;
  final VoidCallback onOpenDevices;
  final VoidCallback onOpenRemote;

  @override
  State<CastPage> createState() => _CastPageState();
}

class _CastPageState extends State<CastPage> {
  bool _mirror = true;
  String? _result;

  void _start() {
    setState(() {
      _result = 'Screen capture is not part of this build. Nothing was captured and no device was contacted.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.discovery,
      builder: (context, _) {
        final snapshot = widget.discovery.snapshot;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeader(
              title: 'Screen casting',
              subtitle: 'Cast to a Mirquova receiver on your LAN. Screen capture permission is requested only when casting can actually start.',
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 760;
                final controls = _Controls(
                  mirror: _mirror,
                  onMirror: (value) => setState(() => _mirror = value),
                  onOpenRemote: widget.onOpenRemote,
                  onStart: _start,
                  result: _result,
                );
                final receivers = _Receivers(
                  snapshot: snapshot,
                  onOpenDevices: widget.onOpenDevices,
                );
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [controls, const SizedBox(height: 16), receivers],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: controls),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: receivers),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.mirror,
    required this.onMirror,
    required this.onOpenRemote,
    required this.onStart,
    required this.result,
  });

  final bool mirror;
  final ValueChanged<bool> onMirror;
  final VoidCallback onOpenRemote;
  final VoidCallback onStart;
  final String? result;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatusChip(
            label: 'Not casting',
            color: Color(0xFF71819A),
            icon: Icons.cast_outlined,
          ),
          const SizedBox(height: 16),
          Text(
            'No receiver selected',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'A discovered name is not a confirmed receiver. Starting a cast checks that capture is available and does not contact a device when it is not.',
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Mirror screen'),
                  icon: Icon(Icons.screenshot_monitor_outlined),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Cast media'),
                  icon: Icon(Icons.movie_outlined),
                ),
              ],
              selected: {mirror},
              onSelectionChanged: (value) => onMirror(value.first),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            mirror ? 'Full-screen mirror stays off until a session exists.' : 'Media casting stays off until playback and a receiver session exist.',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          const _LinkGraphic(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.cast_outlined),
              label: const Text('Start casting'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            result ?? 'Start casting checks this device. It does not begin a session by itself.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onOpenRemote,
            icon: const Icon(Icons.settings_remote_outlined),
            label: const Text('TV remote'),
          ),
        ],
      ),
    );
  }
}

class _LinkGraphic extends StatelessWidget {
  const _LinkGraphic();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.laptop_outlined, size: 42, color: colors.primary),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Divider(color: colors.secondary),
            ),
          ),
          Icon(Icons.tv_outlined, size: 48, color: colors.secondary),
        ],
      ),
    );
  }
}

class _Receivers extends StatelessWidget {
  const _Receivers({required this.snapshot, required this.onOpenDevices});

  final DiscoverySnapshot snapshot;
  final VoidCallback onOpenDevices;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available devices',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Listed devices were seen on the LAN. They are not cast targets yet.',
        ),
        const SizedBox(height: 12),
        if (snapshot.peers.isEmpty)
          EmptyPanel(
            icon: Icons.tv_off_outlined,
            title: 'No receiver found',
            message: snapshot.status == DiscoveryStatus.scanning
                ? 'A scan is running. Results stay unverified.'
                : 'Open Devices to scan this LAN. An empty list is not a failed TV.',
            action: OutlinedButton(
              onPressed: onOpenDevices,
              child: const Text('Open devices'),
            ),
          )
        else
          for (final peer in snapshot.peers)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
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
                  ],
                ),
              ),
            ),
        if (snapshot.peers.isNotEmpty)
          OutlinedButton(
            onPressed: onOpenDevices,
            child: const Text('Open devices'),
          ),
      ],
    );
  }
}
