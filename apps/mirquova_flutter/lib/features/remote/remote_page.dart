import 'package:flutter/material.dart';

import '../../core/playback.dart';
import '../../ui/surface_card.dart';

class RemotePage extends StatelessWidget {
  const RemotePage({
    super.key,
    required this.onBack,
    required this.playback,
    required this.onHome,
  });

  final VoidCallback onBack;
  final LocalPlayback playback;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final connected = playback.hasMedia;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'TV remote',
              subtitle: connected
                  ? 'These buttons control playback on this device. They are not sent to a TV.'
                  : 'Controls stay off until a file is open on this device. Nothing is sent to a TV.',
              trailing: OutlinedButton(
                onPressed: onBack,
                child: const Text('Back to casting'),
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SurfaceCard(
                  child: Column(
                    children: [
                      StatusChip(
                        label: connected ? 'This device' : 'Not connected',
                        color: connected
                            ? const Color(0xFF3DDC97)
                            : const Color(0xFF71819A),
                        icon: connected ? Icons.devices : Icons.link_off,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        playback.name ?? 'No media on this device',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        connected
                            ? 'Direction changes volume and position. OK plays or pauses.'
                            : 'Open a file in Media Player. These buttons do not contact another device.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      _Pad(
                        enabled: connected,
                        onUp: () => playback.changeVolume(0.1),
                        onDown: () => playback.changeVolume(-0.1),
                        onLeft: () =>
                            playback.seekBy(const Duration(seconds: -10)),
                        onRight: () =>
                            playback.seekBy(const Duration(seconds: 10)),
                        onOk: playback.togglePlay,
                        onBack: playback.stop,
                        onHome: onHome,
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _RemoteButton(
                            icon: Icons.remove,
                            tooltip: 'Volume down',
                            onPressed: connected
                                ? () => playback.changeVolume(-0.1)
                                : null,
                          ),
                          _RemoteButton(
                            icon: Icons.add,
                            tooltip: 'Volume up',
                            onPressed: connected
                                ? () => playback.changeVolume(0.1)
                                : null,
                          ),
                          _RemoteButton(
                            icon: Icons.skip_previous,
                            tooltip: 'Back 10 seconds',
                            onPressed: connected
                                ? () => playback.seekBy(
                                    const Duration(seconds: -10),
                                  )
                                : null,
                          ),
                          _RemoteButton(
                            icon: playback.playing
                                ? Icons.pause
                                : Icons.play_arrow,
                            tooltip: 'Play or pause',
                            onPressed: connected ? playback.togglePlay : null,
                          ),
                          _RemoteButton(
                            icon: Icons.skip_next,
                            tooltip: 'Forward 10 seconds',
                            onPressed: connected
                                ? () => playback.seekBy(
                                    const Duration(seconds: 10),
                                  )
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: connected ? playback.stop : null,
                        child: const Text('Disconnect'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Pad extends StatelessWidget {
  const _Pad({
    required this.enabled,
    required this.onUp,
    required this.onDown,
    required this.onLeft,
    required this.onRight,
    required this.onOk,
    required this.onBack,
    required this.onHome,
  });

  final bool enabled;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onLeft;
  final VoidCallback onRight;
  final VoidCallback onOk;
  final VoidCallback onBack;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RemoteButton(
              icon: Icons.arrow_back,
              tooltip: 'Stop playback',
              onPressed: enabled ? onBack : null,
            ),
            const SizedBox(width: 12),
            _RemoteButton(
              icon: Icons.keyboard_arrow_up,
              tooltip: 'Volume up',
              onPressed: enabled ? onUp : null,
            ),
            const SizedBox(width: 12),
            _RemoteButton(
              icon: Icons.home_outlined,
              tooltip: 'Home',
              onPressed: onHome,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RemoteButton(
              icon: Icons.keyboard_arrow_left,
              tooltip: 'Back 10 seconds',
              onPressed: enabled ? onLeft : null,
            ),
            const SizedBox(width: 8),
            _OkButton(onPressed: enabled ? onOk : null),
            const SizedBox(width: 8),
            _RemoteButton(
              icon: Icons.keyboard_arrow_right,
              tooltip: 'Forward 10 seconds',
              onPressed: enabled ? onRight : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _RemoteButton(
          icon: Icons.keyboard_arrow_down,
          tooltip: 'Volume down',
          onPressed: enabled ? onDown : null,
        ),
      ],
    );
  }
}

class _OkButton extends StatelessWidget {
  const _OkButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: 'Play or pause',
      child: IconButton.filled(
        onPressed: onPressed,
        icon: const Text(
          'OK',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        style: IconButton.styleFrom(
          fixedSize: const Size(76, 76),
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

class _RemoteButton extends StatelessWidget {
  const _RemoteButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
    );
  }
}
