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
        'This is a Mirquova screen share on $size. Nothing is sent to Chromecast or a TV unless that device is running Mirquova and you accept.',
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Screen from $sender'),
        automaticallyImplyLeading: false,
        actions: [TextButton(onPressed: _stop, child: const Text('Stop'))],
      ),
      body: ColoredBox(
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
    );
  }
}
