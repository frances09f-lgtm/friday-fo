import 'dart:math' as math;
import 'package:flutter/material.dart';

/// State animation, not an audio-level meter. Gestures never submit commands.
enum GlobeMode { idle, listening, thinking, speaking }

class ResponsiveGlobe extends StatefulWidget {
  const ResponsiveGlobe(
      {super.key,
      required this.mode,
      this.onTap,
      this.active = true,
      this.size = 148});
  final GlobeMode mode;
  final VoidCallback? onTap;
  final bool active;
  final double size;
  @override
  State<ResponsiveGlobe> createState() => _ResponsiveGlobeState();
}

class _ResponsiveGlobeState extends State<ResponsiveGlobe>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion;
  double _yaw = .18, _pitch = -.12;
  bool _foreground = true;
  bool _reduced = false;
  @override
  void initState() {
    super.initState();
    _motion =
        AnimationController(vsync: this, duration: const Duration(seconds: 4));
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(ResponsiveGlobe oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    final animate = !_reduced &&
        _foreground &&
        widget.active &&
        TickerMode.valuesOf(context).enabled &&
        widget.mode != GlobeMode.idle;
    if (animate && !_motion.isAnimating) {
      _motion.repeat();
    } else if (!animate && _motion.isAnimating) {
      _motion.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  String get _label => switch (widget.mode) {
        GlobeMode.idle => 'Friday globe. Tap to talk. Drag to rotate.',
        GlobeMode.listening =>
          'Friday is listening. Tap to stop listening. Drag to rotate.',
        GlobeMode.thinking => 'Friday is working. Drag to rotate.',
        GlobeMode.speaking =>
          'Friday is speaking. Tap to stop speaking. Drag to rotate.',
      };
  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _label,
      button: widget.onTap != null,
      onTap: widget.onTap,
      child: ExcludeSemantics(
          child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        // Horizontal drag leaves vertical page scrolling available. A diagonal
        // gesture that wins here only rotates; it can never start the mic.
        onHorizontalDragUpdate: (d) => setState(() {
          _yaw += d.delta.dx / widget.size * 3;
          _pitch = (_pitch + d.delta.dy / widget.size * 2).clamp(-.65, .65);
        }),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: RepaintBoundary(
              child: AnimatedBuilder(
            animation: _motion,
            builder: (_, __) => CustomPaint(
                painter: GlobePainter(
              mode: widget.mode,
              phase: _reduced ? 0 : _motion.value,
              yaw: _yaw,
              pitch: _pitch,
              reducedMotion: _reduced,
            )),
          )),
        ),
      )),
    );
  }
}

class GlobePainter extends CustomPainter {
  const GlobePainter(
      {required this.mode,
      required this.phase,
      required this.yaw,
      required this.pitch,
      this.reducedMotion = false});
  final GlobeMode mode;
  final double phase, yaw, pitch;
  final bool reducedMotion;
  Color get tint => switch (mode) {
        GlobeMode.idle => const Color(0xFF3CD4DF),
        GlobeMode.listening => const Color(0xFF5DE4DC),
        GlobeMode.thinking => const Color(0xFFB3BFFF),
        GlobeMode.speaking => const Color(0xFF85BFFF),
      };
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final pulse = reducedMotion || mode == GlobeMode.idle
        ? 0.0
        : (math.sin(phase * math.pi * (mode == GlobeMode.speaking ? 12 : 4)) +
                1) /
            2;
    final r = size.shortestSide * (.375 + pulse * .016);
    canvas.drawCircle(
        c,
        r * 1.24,
        Paint()
          ..shader = RadialGradient(colors: [
            tint.withValues(alpha: .13 + pulse * .05),
            tint.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: c, radius: r * 1.24)));
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-.4, -.5),
            colors: [Color(0xFF214657), Color(0xFF101C2C), Color(0xFF0B1320)],
          ).createShader(Rect.fromCircle(center: c, radius: r)));
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    final rotation = yaw +
        (mode == GlobeMode.thinking && !reducedMotion
            ? phase * math.pi * 2
            : 0);
    List<double> project(double lat, double lon) {
      final a = lat * math.pi / 180, b = lon * math.pi / 180 + rotation;
      final x = math.cos(a) * math.sin(b);
      final y = math.sin(a), z = math.cos(a) * math.cos(b);
      return [
        c.dx + r * x,
        c.dy - r * (y * math.cos(pitch) - z * math.sin(pitch)),
        y * math.sin(pitch) + z * math.cos(pitch)
      ];
    }

    void line(List<List<double>> points) {
      var path = Path();
      var connected = false;
      for (final ll in points) {
        final p = project(ll[0], ll[1]);
        if (p[2] > 0) {
          if (connected) {
            path.lineTo(p[0], p[1]);
          } else {
            path.moveTo(p[0], p[1]);
          }
          connected = true;
        } else {
          connected = false;
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = tint.withValues(alpha: .14)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .65);
    }

    for (var lat = -60; lat <= 60; lat += 30) {
      line([
        for (var lon = -180; lon <= 180; lon += 3)
          [lat.toDouble(), lon.toDouble()]
      ]);
    }
    for (var lon = -180; lon < 180; lon += 30) {
      line([
        for (var lat = -90; lat <= 90; lat += 3)
          [lat.toDouble(), lon.toDouble()]
      ]);
    }
    // Coarse, decorative land silhouettes, not geographic/navigation data.
    for (final point in _landDots) {
      final p = project(point[1], point[0]);
      if (p[2] > .015) {
        canvas.drawCircle(Offset(p[0], p[1]), (r * .014).clamp(.6, 2.2),
            Paint()..color = tint.withValues(alpha: .3 + p[2] * .6));
      }
    }
    canvas.restore();
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = tint.withValues(alpha: .55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    if (mode != GlobeMode.idle) {
      final halo = r + 6 + pulse * 5;
      canvas.drawCircle(
          c,
          halo,
          Paint()
            ..color = tint.withValues(alpha: .18 + pulse * .12)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
      if (mode == GlobeMode.listening || mode == GlobeMode.speaking) {
        for (var i = 0; i < 24; i++) {
          final a = i * math.pi / 12;
          final wave = reducedMotion
              ? .35
              : (math.sin(phase * math.pi * 8 + i * .7) + 1) / 2;
          final start = Offset(
              c.dx + math.cos(a) * (r + 14), c.dy + math.sin(a) * (r + 14));
          final end = Offset(c.dx + math.cos(a) * (r + 16 + wave * 5),
              c.dy + math.sin(a) * (r + 16 + wave * 5));
          canvas.drawLine(
              start,
              end,
              Paint()
                ..color = tint.withValues(alpha: .3 + wave * .5)
                ..strokeWidth = 1.8
                ..strokeCap = StrokeCap.round);
        }
      }
    }
  }

  @override
  bool shouldRepaint(GlobePainter old) =>
      mode != old.mode ||
      phase != old.phase ||
      yaw != old.yaw ||
      pitch != old.pitch ||
      reducedMotion != old.reducedMotion;
}

const _continents = <List<Offset>>[
  [
    Offset(-168, 70),
    Offset(-130, 73),
    Offset(-105, 60),
    Offset(-82, 55),
    Offset(-55, 50),
    Offset(-68, 30),
    Offset(-81, 24),
    Offset(-98, 16),
    Offset(-110, 28),
    Offset(-125, 48),
    Offset(-155, 58)
  ],
  [
    Offset(-81, 12),
    Offset(-63, 10),
    Offset(-47, -1),
    Offset(-35, -10),
    Offset(-50, -30),
    Offset(-69, -55),
    Offset(-76, -30)
  ],
  [
    Offset(-17, 35),
    Offset(9, 37),
    Offset(33, 30),
    Offset(50, 11),
    Offset(40, -12),
    Offset(18, -35),
    Offset(8, -20),
    Offset(-3, 5),
    Offset(-17, 15)
  ],
  [
    Offset(-10, 36),
    Offset(-10, 58),
    Offset(20, 70),
    Offset(58, 67),
    Offset(100, 76),
    Offset(175, 65),
    Offset(155, 45),
    Offset(140, 35),
    Offset(125, 8),
    Offset(105, -5),
    Offset(80, 8),
    Offset(70, 25),
    Offset(45, 30),
    Offset(28, 42),
    Offset(7, 42)
  ],
  [
    Offset(113, -22),
    Offset(130, -12),
    Offset(145, -15),
    Offset(153, -28),
    Offset(142, -39),
    Offset(116, -34)
  ],
  [
    Offset(-54, 59),
    Offset(-30, 65),
    Offset(-22, 82),
    Offset(-48, 84),
    Offset(-65, 74)
  ],
];
bool _inside(Offset p, List<Offset> polygon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i], b = polygon[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

final _landDots = <List<double>>[
  for (var lat = -54; lat <= 81; lat += 5)
    for (var lon = -177; lon <= 177; lon += 5)
      if (_continents
          .any((p) => _inside(Offset(lon.toDouble(), lat.toDouble()), p)))
        [lon.toDouble(), lat.toDouble()],
];
