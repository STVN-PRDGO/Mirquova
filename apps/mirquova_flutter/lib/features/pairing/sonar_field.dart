import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/discovery_port.dart';

class SonarField extends StatefulWidget {
  const SonarField({
    super.key,
    required this.peers,
    required this.scanning,
    required this.selectedId,
    required this.onSelect,
  });

  final List<PeerCandidate> peers;
  final bool scanning;
  final String? selectedId;
  final ValueChanged<PeerCandidate> onSelect;

  @override
  State<SonarField> createState() => _SonarFieldState();
}

class _SonarFieldState extends State<SonarField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(SonarField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (widget.scanning && !reduce) {
      if (!_sweep.isAnimating) _sweep.repeat();
    } else {
      _sweep.stop();
      _sweep.value = 0;
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final shown = widget.peers.take(8).toList();
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surfaceContainerLowest,
          border: Border.all(color: colors.outline),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _sweep,
                builder: (context, _) => CustomPaint(
                  painter: _SonarPainter(
                    sweep: _sweep.value,
                    scanning: widget.scanning && !reduce,
                    colors: colors,
                  ),
                ),
              ),
            ),
            const _CenterMark(),
            for (var i = 0; i < shown.length; i++)
              _PeerBlip(
                peer: shown[i],
                index: i,
                count: shown.length,
                selected: shown[i].id == widget.selectedId,
                reduceMotion: reduce,
                onSelect: widget.onSelect,
              ),
          ],
        ),
      ),
    );
  }
}

class _CenterMark extends StatelessWidget {
  const _CenterMark();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'This device',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary,
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.45),
                  blurRadius: 16,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'You',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PeerBlip extends StatelessWidget {
  const _PeerBlip({
    required this.peer,
    required this.index,
    required this.count,
    required this.selected,
    required this.reduceMotion,
    required this.onSelect,
  });

  final PeerCandidate peer;
  final int index;
  final int count;
  final bool selected;
  final bool reduceMotion;
  final ValueChanged<PeerCandidate> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final angle = (index / math.max(count, 1)) * math.pi * 2 - math.pi / 2;
    final ring = 0.38 + (index % 3) * 0.16;
    return Align(
      alignment: Alignment(math.cos(angle) * ring, math.sin(angle) * ring),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduceMotion ? 1 : 0.4, end: 1),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Semantics(
          button: true,
          selected: selected,
          label: '${peer.name}, nearby, not connected',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onSelect(peer),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      width: selected ? 16 : 12,
                      height: selected ? 16 : 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? colors.secondary : colors.tertiary,
                        boxShadow: [
                          BoxShadow(
                            color:
                                (selected ? colors.secondary : colors.tertiary)
                                    .withValues(alpha: 0.55),
                            blurRadius: selected ? 14 : 8,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: 72,
                      child: Text(
                        peer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurface,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SonarPainter extends CustomPainter {
  const _SonarPainter({
    required this.sweep,
    required this.scanning,
    required this.colors,
  });

  final double sweep;
  final bool scanning;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 8;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = colors.outline.withValues(alpha: 0.85);
    for (final factor in [0.34, 0.58, 0.82]) {
      canvas.drawCircle(center, radius * factor, ring);
    }
    if (!scanning) return;
    final ping = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = colors.secondary.withValues(alpha: (1 - sweep) * 0.75);
    canvas.drawCircle(center, radius * (0.18 + 0.72 * sweep), ping);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(sweep * math.pi * 2);
    final wedge = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 0.9,
        colors: [
          colors.secondary.withValues(alpha: 0.38),
          colors.secondary.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: radius * 0.82),
      0,
      0.9,
      true,
      wedge,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SonarPainter oldDelegate) =>
      oldDelegate.sweep != sweep ||
      oldDelegate.scanning != scanning ||
      oldDelegate.colors != colors;
}
