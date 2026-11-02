import 'dart:async';

import 'package:flutter/material.dart';

import 'mirquova_mark.dart';

/// Continues the native launch screen: the mark starts where Android drew it,
/// the wordmark rises in, then the whole layer fades into the app.
class LaunchIntro extends StatefulWidget {
  const LaunchIntro({super.key, required this.child});

  final Widget child;

  static const background = Color(0xFF080D18);
  static const duration = Duration(milliseconds: 1800);

  @override
  State<LaunchIntro> createState() => _LaunchIntroState();
}

class _LaunchIntroState extends State<LaunchIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: LaunchIntro.duration,
  );
  bool _done = false;
  bool _started = false;
  bool _reduceMotion = false;
  Timer? _hold;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_done || _started) return;
    _started = true;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      // A disabled ticker never completes. Each tick schedules a frame so the
      // splash leaves on its own and tests are not left with a pending timer.
      var ticks = 0;
      _hold = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!mounted) return;
        ticks++;
        if (ticks * 100 >= LaunchIntro.duration.inMilliseconds) {
          timer.cancel();
          _hold = null;
          setState(() => _done = true);
        } else {
          setState(() {});
        }
      });
      return;
    }
    _controller.forward().whenCompleteOrCancel(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _hold?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _interval(
    double begin,
    double end, [
    Curve curve = Curves.easeOutCubic,
  ]) => CurvedAnimation(
    parent: _controller,
    curve: Interval(begin, end, curve: curve),
  );

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      if (!_done)
        Positioned.fill(
          child: IgnorePointer(child: ExcludeSemantics(child: _overlay())),
        ),
    ],
  );

  Widget _still(TextTheme textTheme) => ColoredBox(
    color: LaunchIntro.background,
    child: SafeArea(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MirquovaMark(size: 112),
            const SizedBox(height: 28),
            Text(
              'Mirquova',
              style: textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Every screen. One connection.',
              style: textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFA7B4C8),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _overlay() {
    final pulse = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1, end: 1.08), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1), weight: 1),
    ]).animate(_interval(0, 0.4, Curves.easeInOut));
    final ring = _interval(0.08, 0.62);
    final word = _interval(0.22, 0.52);
    final tagline = _interval(0.32, 0.62);
    final exit = _interval(0.78, 1, Curves.easeInCubic);
    if (_reduceMotion) return _still(Theme.of(context).textTheme);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final textTheme = Theme.of(context).textTheme;
        return Opacity(
          opacity: 1 - exit.value,
          child: ColoredBox(
            color: LaunchIntro.background,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: (1 - ring.value) * 0.55,
                  child: Container(
                    width: 112 + 220 * ring.value,
                    height: 112 + 220 * ring.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF22D3EE),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                Transform.scale(
                  scale: pulse.value + 0.12 * exit.value,
                  child: const MirquovaMark(size: 112),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 112 + 96),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.translate(
                          offset: Offset(0, 14 * (1 - word.value)),
                          child: Opacity(
                            opacity: word.value,
                            child: Text(
                              'Mirquova',
                              style: textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Opacity(
                          opacity: tagline.value,
                          child: Text(
                            'Every screen. One connection.',
                            style: textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFFA7B4C8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
