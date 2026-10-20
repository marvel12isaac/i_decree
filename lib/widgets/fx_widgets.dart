// lib/widgets/fx_widgets.dart
// Small, dependency-free effect widgets. All of them read Fx.level, so the
// Full / Reduced / Off setting and the phone's animation setting apply
// everywhere without each screen having to care.

import 'dart:math';

import 'package:flutter/material.dart';

import '../fx.dart';

// ---------------------------------------------------------------- count up

/// A number that counts to its new value when it CHANGES. The first time it
/// appears it just shows the value (no count-from-zero on every screen visit).
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.value,
    this.style,
    this.suffix = '',
  });

  final int value;
  final TextStyle? style;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.toDouble()),
      duration: Fx.dur(Fx.standard),
      curve: Fx.easeOut,
      builder: (context, v, _) => Text('${v.round()}$suffix', style: style),
    );
  }
}

// ------------------------------------------------------------------ pop in

/// Scales and fades its child in once, when it first appears. Use it for the
/// crown/check that has just been earned: set [animate] true only for the
/// one that just changed, so the rest stay still.
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.child, this.animate = true});

  final Widget child;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (!animate || Fx.isOff) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.6, end: 1),
      duration: Fx.dur(Fx.pop),
      curve: Fx.springy,
      child: child,
      builder: (context, v, c) => Transform.scale(
        scale: v,
        child: Opacity(
          opacity: ((v - 0.6) / 0.4).clamp(0.0, 1.0).toDouble(),
          child: c,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ fade + slide

/// Fades and slides its child up slightly, once, when first built. Use for
/// the decree text reveal and for first-load list entry (pass
/// `animate: Fx.firstTime('home_list')`). [index] adds a small stagger in
/// Full mode only (capped, so long lists don't wait).
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.animate = true,
    this.index = 0,
    this.offset = 12,
  });

  final Widget child;
  final bool animate;
  final int index;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _t;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.animate || Fx.isOff) return;
    final staggerMs = Fx.isFull ? widget.index.clamp(0, 6) * 40 : 0;
    final total = Fx.dur(Fx.standard) + Duration(milliseconds: staggerMs);
    if (total.inMilliseconds <= 0) return;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    _t = CurvedAnimation(
      parent: controller,
      curve: Interval(
        staggerMs / total.inMilliseconds,
        1,
        curve: Fx.easeOut,
      ),
    );
    controller.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return widget.child;
    return FadeTransition(
      opacity: t,
      child: AnimatedBuilder(
        animation: t,
        child: widget.child,
        builder: (context, c) => Transform.translate(
          offset: Offset(0, (1 - t.value) * widget.offset),
          child: c,
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- pulse once

/// Pulses its child once (about 1.18x and back) whenever [trigger] changes.
/// Full mode only. Use on the saves shield: trigger = the saves number.
class PulseOnce extends StatefulWidget {
  const PulseOnce({super.key, required this.trigger, required this.child});

  final Object? trigger;
  final Widget child;

  @override
  State<PulseOnce> createState() => _PulseOnceState();
}

class _PulseOnceState extends State<PulseOnce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Fx.standard);
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 1, end: 1.18)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.18, end: 1)
          .chain(CurveTween(curve: Curves.easeIn)),
      weight: 60,
    ),
  ]).animate(_c);

  @override
  void didUpdateWidget(PulseOnce oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger && Fx.isFull) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}

// ------------------------------------------------------------ hold progress

/// Draws a progress ring around [child] while [progress] runs 0..1. Meant for
/// the hold-to-read button: feed it the hold animation. The ring follows the
/// child's outline (a circle for a square child, a pill for a wide one).
/// It is functional feedback, so it shows at every effects level.
class HoldRing extends StatelessWidget {
  const HoldRing({
    super.key,
    required this.progress,
    required this.child,
    this.color,
    this.strokeWidth = 3,
  });

  final Animation<double> progress;
  final Widget child;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _RingPainter(
        progress,
        color ?? Theme.of(context).colorScheme.primary,
        strokeWidth,
      ),
      child: child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color, this.strokeWidth)
      : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value.clamp(0.0, 1.0).toDouble();
    if (p <= 0) return;
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        rect,
        Radius.circular(rect.shortestSide / 2),
      ));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * p), paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

// ----------------------------------------------------------------- confetti

/// A one-shot burst of about 30 small pieces (no package). Inserted into the
/// root overlay by Fx.afterRead; removes itself when done. Full mode only.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, required this.onDone, this.count = 30});

  final VoidCallback onDone;
  final int count;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _Piece {
  _Piece({
    required this.angle,
    required this.speed,
    required this.size,
    required this.spin,
    required this.phase,
    required this.color,
  });

  final double angle;
  final double speed;
  final double size;
  final double spin;
  final double phase;
  final Color color;
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  static const List<Color> _colors = [
    Color(0xFF1FA89A),
    Color(0xFFF28C28),
    Color(0xFFFFC53D),
    Color(0xFF3B82F6),
    Color(0xFF7C5CFF),
  ];

  late final AnimationController _controller;
  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    final rnd = Random();
    _pieces = List.generate(widget.count, (i) {
      return _Piece(
        angle: -pi / 2 + (rnd.nextDouble() - 0.5) * 2.2,
        speed: 380 + rnd.nextDouble() * 360,
        size: 7 + rnd.nextDouble() * 6,
        spin: (rnd.nextDouble() - 0.5) * 14,
        phase: rnd.nextDouble() * pi,
        color: _colors[rnd.nextInt(_colors.length)],
      );
    });
    _controller = AnimationController(vsync: this, duration: Fx.celebrate)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(painter: _ConfettiPainter(_controller, _pieces)),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.pieces) : super(repaint: t);

  final Animation<double> t;
  final List<_Piece> pieces;

  @override
  void paint(Canvas canvas, Size size) {
    final p = t.value;
    final secs = p * (Fx.celebrate.inMilliseconds / 1000);
    final origin = Offset(size.width / 2, size.height * 0.38);
    final fade = p < 0.7 ? 1.0 : (1 - (p - 0.7) / 0.3).clamp(0.0, 1.0);
    final paint = Paint();
    for (final c in pieces) {
      final dx = cos(c.angle) * c.speed * secs;
      final dy = sin(c.angle) * c.speed * secs + 0.5 * 900 * secs * secs;
      paint.color = c.color.withAlpha((255 * fade).round());
      canvas.save();
      canvas.translate(origin.dx + dx, origin.dy + dy);
      canvas.rotate(c.spin * secs + c.phase);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: c.size,
          height: c.size * 0.55,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}

// --------------------------------------------------------- settings picker

/// The "Effects" choice for the Settings page: Automatic / Full / Reduced /
/// Off. Drop it into the Settings screen as-is.
class EffectsPicker extends StatelessWidget {
  const EffectsPicker({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FxLevel?>(
      valueListenable: Fx.choice,
      builder: (context, choice, _) {
        Widget option(String title, String subtitle, FxLevel? value) {
          return ListTile(
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: choice == value ? const Icon(Icons.check) : null,
            onTap: () => Fx.setChoice(value),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Effects'),
            ),
            option('Automatic', 'Follows your phone\u2019s animation setting',
                null),
            option('Full', 'All animations and celebrations', FxLevel.full),
            option('Reduced', 'Shorter animations, no celebrations',
                FxLevel.reduced),
            option('Off', 'No animations or vibration', FxLevel.off),
          ],
        );
      },
    );
  }
}