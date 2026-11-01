import 'package:flutter/material.dart';

import '../../adapters/native_cast.dart';
import '../../adapters/pairing_identity.dart';
import '../../core/cast_state.dart';
import '../../ui/surface_card.dart';

class CastPage extends StatefulWidget {
  const CastPage({
    super.key,
    required this.service,
    required this.onOpenPair,
    required this.onOpenDevices,
    required this.onOpenRemote,
  });

  final CastService? service;
  final VoidCallback onOpenPair;
  final VoidCallback onOpenDevices;
  final VoidCallback onOpenRemote;

  @override
  State<CastPage> createState() => _CastPageState();
}

class _CastPageState extends State<CastPage> {
  bool _mirror = true;

  @override
  void initState() {
    super.initState();
    widget.service?.reloadPeers();
  }

  Future<void> _start(TrustedPeer peer) async {
    final service = widget.service;
    if (service == null || service.sending) return;
    await service.startCast(peer: peer);
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    const header = PageHeader(
      title: 'Screen casting',
      subtitle: 'Share this screen with a paired Mirquova device. The other device accepts before anything is shown.',
    );
    if (service == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 16),
          EmptyPanel(
            icon: Icons.error_outline,
            title: 'Screen casting is unavailable',
            message: 'This build does not include the Mirquova native core. Install the full app package.',
            action: OutlinedButton(
              onPressed: widget.onOpenDevices,
              child: const Text('Open devices'),
            ),
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final outgoing = service.outgoing;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            const SizedBox(height: 16),
            _ReceiveStatus(service: service),
            const SizedBox(height: 16),
            _Controls(
              mirror: _mirror,
              supported: service.captureSupported,
              sending: service.sending,
              onMirror: (value) => setState(() => _mirror = value),
              onOpenRemote: widget.onOpenRemote,
              onStop: service.stopOutgoing,
              snapshot: outgoing,
              message: service.sendMessage,
            ),
            const SizedBox(height: 20),
            if (service.peers.isEmpty)
              EmptyPanel(
                icon: Icons.devices_other_outlined,
                title: 'No paired devices yet',
                message: 'Pair once, then tap a device here. A discovered name is not a cast target until it is paired.',
                action: Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: widget.onOpenPair,
                      icon: const Icon(Icons.radar_outlined),
                      label: const Text('Pair a device'),
                    ),
                    OutlinedButton(
                      onPressed: widget.onOpenDevices,
                      child: const Text('Open devices'),
                    ),
                  ],
                ),
              )
            else ...[
              Text(
                service.sending
                    ? 'Sharing to'
                    : 'Tap a device to share this screen',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final peer in service.peers)
                    _DeviceTile(
                      peer: peer,
                      enabled: !service.sending && service.captureSupported,
                      active:
                          service.outgoingPeer?.fingerprintSha256 ==
                          peer.fingerprintSha256,
                      onTap: () => _start(peer),
                    ),
                  _AddDeviceTile(onTap: widget.onOpenPair),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ReceiveStatus extends StatelessWidget {
  const _ReceiveStatus({required this.service});

  final CastService service;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final problem = service.receiveProblem;
    final ready = service.receiving && problem == null;
    final color = problem != null
        ? colors.error
        : ready
        ? Colors.green.shade600
        : colors.onSurfaceVariant;
    final label =
        problem ??
        (ready
            ? 'Ready to receive a screen share from paired devices'
            : service.peers.isEmpty
            ? 'Pair a device to receive a screen share'
            : 'Starting…');
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            ready ? Icons.cast_connected : Icons.cast_outlined,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.mirror,
    required this.supported,
    required this.sending,
    required this.onMirror,
    required this.onOpenRemote,
    required this.onStop,
    required this.snapshot,
    required this.message,
  });

  final bool mirror;
  final bool supported;
  final bool sending;
  final ValueChanged<bool> onMirror;
  final VoidCallback onOpenRemote;
  final VoidCallback onStop;
  final CastSnapshot snapshot;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final live = snapshot.status == CastStatus.casting;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusChip(
            label: live
                ? 'Sharing this screen'
                : snapshot.status == CastStatus.awaitingApproval
                ? 'Waiting for approval'
                : snapshot.status == CastStatus.connecting
                ? 'Connecting'
                : 'Not sharing',
            color: live ? const Color(0xFF3DDC97) : const Color(0xFF71819A),
            icon: live ? Icons.cast_connected : Icons.cast_outlined,
          ),
          const SizedBox(height: 16),
          Text(
            supported
                ? 'Mirquova-to-Mirquova screen share'
                : 'Screen capture is not available on this device',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            supported
                ? 'This shares JPEG frames of this screen over the same trusted pairing used for files. It is not Chromecast or Miracast.'
                : 'This build can still receive a screen share from a Windows or Android device that is paired here.',
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
              onSelectionChanged: sending
                  ? null
                  : (value) => onMirror(value.first),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            mirror
                ? 'The whole screen is shared after the other device accepts.'
                : 'Media casting in this build still shares the screen, including the player if it is open.',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          if (sending || message != null) ...[
            const SizedBox(height: 16),
            if (sending) const LinearProgressIndicator(),
            if (message != null) ...[const SizedBox(height: 8), Text(message!)],
          ],
          const SizedBox(height: 20),
          if (sending)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop sharing'),
              ),
            )
          else
            Text(
              supported ? 'Choose a paired device below to start.' : 'Pair a Windows or Android device, then accept when it shares here.',
              style: TextStyle(color: colors.onSurfaceVariant),
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

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.peer,
    required this.enabled,
    required this.active,
    required this.onTap,
  });

  final TrustedPeer peer;
  final bool enabled;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Share screen to ${peer.alias}',
      child: Material(
        color: active ? colors.primaryContainer : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onTap : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: enabled || active ? 1 : 0.55,
            child: SizedBox(
              width: 132,
              height: 120,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    child: const Icon(Icons.cast_outlined),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      peer.alias,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddDeviceTile extends StatelessWidget {
  const _AddDeviceTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          width: 132,
          height: 120,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 28, color: colors.primary),
              const SizedBox(height: 10),
              const Text('Pair another'),
            ],
          ),
        ),
      ),
    );
  }
}
