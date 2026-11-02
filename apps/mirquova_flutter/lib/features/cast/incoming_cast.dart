import 'package:flutter/material.dart';

import '../../adapters/native_cast.dart';

/// Shown over any screen while a paired device waits to share its display.
class IncomingCastDialog extends StatefulWidget {
  const IncomingCastDialog({super.key, required this.service});

  final CastService service;

  @override
  State<IncomingCastDialog> createState() => _IncomingCastDialogState();
}

class _IncomingCastDialogState extends State<IncomingCastDialog> {
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_changed);
  }

  @override
  void dispose() {
    widget.service.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted || _closed) return;
    if (!widget.service.incomingNeedsAnswer) {
      _closed = true;
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  void _answer(bool accept) {
    if (_closed) return;
    _closed = true;
    accept ? widget.service.approve() : widget.service.reject();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sender = widget.service.incomingPeer?.alias ?? 'A paired device';
    final snapshot = widget.service.incoming;
    final size = snapshot.width != null && snapshot.height != null
        ? '${snapshot.width}×${snapshot.height}'
        : 'this LAN';
    return AlertDialog(
      icon: Icon(Icons.cast_rounded, color: theme.colorScheme.primary),
      title: Text('$sender wants to share a screen'),
      content: Text(
        'This is a Mirquova screen share on $size.${snapshot.audio ? ' Accepting also plays that device\'s system audio here. The microphone is not included.' : ''} Nothing is sent to Chromecast or a TV unless that device is running Mirquova and you accept. If you do nothing, this is declined after 60 seconds.',
      ),
      actions: [
        TextButton(
          onPressed: () => _answer(false),
          child: const Text('Decline'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => _answer(true),
          child: const Text('Accept'),
        ),
      ],
    );
  }
}

/// Full-screen viewer for an accepted incoming screen share.
class IncomingCastViewer extends StatefulWidget {
  const IncomingCastViewer({super.key, required this.service});

  final CastService service;

  @override
  State<IncomingCastViewer> createState() => _IncomingCastViewerState();
}

class _IncomingCastViewerState extends State<IncomingCastViewer> {
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_changed);
  }

  @override
  void dispose() {
    widget.service.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted || _closed) return;
    if (!widget.service.incomingLive) {
      _closed = true;
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  void _stop() {
    if (_closed) return;
    _closed = true;
    widget.service.stopIncoming();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sender = widget.service.incomingPeer?.alias ?? 'A paired device';
    final frame = widget.service.incomingFrame;
    final muted = widget.service.playbackMuted;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.black,
              child: Center(
                child: frame == null
                    ? Text(
                        'Waiting for the first frame…',
                        style: TextStyle(color: colors.onInverseSurface),
                      )
                    : Image.memory(
                        frame,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                        fit: BoxFit.contain,
                      ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 0,
              child: SafeArea(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Screen from $sender',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        IconButton(
                          tooltip: muted ? 'Unmute' : 'Mute',
                          onPressed: () =>
                              widget.service.setPlaybackMuted(!muted),
                          icon: Icon(
                            muted
                                ? Icons.volume_off_outlined
                                : Icons.volume_up_outlined,
                            color: Colors.white,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _stop,
                          icon: const Icon(Icons.fullscreen_exit),
                          label: const Text('Exit'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
