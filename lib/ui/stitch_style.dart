import 'dart:math' as math;
import 'package:flutter/material.dart';

class Stitch {
  static const bg = Color(0xFF10131B);
  static const low = Color(0xFF181B23);
  static const high = Color(0xFF272A32);
  static const ink = Color(0xFFE0E2ED);
  static const muted = Color(0xFFC3C6D6);
  static const blue = Color(0xFFB2C5FF);
  static const cyan = Color(0xFF42D9E6);
  static const green = Color(0xFF4EDEA3);
  static TextStyle mono([double size = 11, Color color = muted]) => TextStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: size,
      color: color,
      letterSpacing: .7);
  static TextStyle title([double size = 26]) => TextStyle(
      fontFamily: 'SpaceGrotesk',
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: ink,
      letterSpacing: -.6);
  static ThemeData theme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      fontFamily: 'Inter',
      colorScheme: const ColorScheme.dark(
          primary: blue,
          secondary: cyan,
          tertiary: green,
          surface: bg,
          onSurface: ink,
          onSurfaceVariant: muted,
          surfaceContainerLow: low,
          surfaceContainerHigh: high),
      appBarTheme: const AppBarTheme(backgroundColor: bg, foregroundColor: ink),
      cardTheme: CardThemeData(
          color: low,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: low,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none)));
}

class StitchCard extends StatelessWidget {
  const StitchCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.color = Stitch.low});
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      child: Padding(padding: padding, child: child));
}

class CoreLogo extends StatelessWidget {
  const CoreLogo({super.key, this.size = 28});
  final double size;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: OrbPainter(compact: true));
}

class FridayOrb extends StatelessWidget {
  const FridayOrb({super.key, this.size = 224, this.voice = false});
  final double size;
  final bool voice;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: OrbPainter(voice: voice));
}

class OrbPainter extends CustomPainter {
  OrbPainter({this.voice = false, this.compact = false});
  final bool voice, compact;
  @override
  void paint(Canvas c, Size s) {
    final center = s.center(Offset.zero), r = s.width / 2;
    final p = Paint();
    p.color = Colors.white;
    p.shader = RadialGradient(colors: [
      Stitch.cyan.withValues(alpha: .18),
      Stitch.bg.withValues(alpha: 0)
    ]).createShader(Offset.zero & s);
    c.drawCircle(center, r, p);
    p.shader = null;
    if (voice) {
      for (int i = 0; i < 3; i++) {
        p.color = Stitch.cyan.withValues(alpha: .10 + i * .04);
        c.drawCircle(center, r * (.96 - i * .10), p);
      }
      p.color = Stitch.cyan.withValues(alpha: .25);
      p.maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      c.drawCircle(center, r * .51, p);
      p.maskFilter = null;
      p.color = Colors.white;
      p.shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF42D9E6), Color(0xFF5B8CFF), Color(0xFF182232)])
          .createShader(Offset.zero & s);
      c.drawCircle(center, r * .67, p);
      p.shader = null;
      p.color = const Color(0xFF23304D);
      final audio = center + Offset(r * .43, 0);
      c.drawCircle(audio, r * .24, p);
      p.color = Stitch.cyan;
      for (int i = 0; i < 5; i++) {
        final h = [.10, .17, .24, .15, .09][i] * r;
        c.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: audio + Offset((i - 2) * r * .035, 0),
                    width: r * .014,
                    height: h),
                Radius.circular(r * .007)),
            p);
      }
      p.style = PaintingStyle.stroke;
      p.strokeWidth = 2;
      p.color = const Color(0xFF23304D).withValues(alpha: .5);
      c.drawCircle(center + Offset(-r * .22, 0), r * .19, p);
      p.style = PaintingStyle.fill;
    } else {
      p.style = PaintingStyle.stroke;
      p.strokeWidth = compact ? 1 : 1.1;
      p.color = Stitch.cyan.withValues(alpha: .45);
      for (int i = 0; i < 30; i++)
        c.drawArc(Rect.fromCircle(center: center, radius: r * .94),
            i * math.pi / 15, .04, false, p);
      p.color = Stitch.blue.withValues(alpha: .5);
      for (int i = 0; i < 12; i++)
        c.drawArc(Rect.fromCircle(center: center, radius: r * .72),
            i * math.pi / 6, .14, false, p);
      p.style = PaintingStyle.fill;
      p.color = Stitch.cyan.withValues(alpha: .25);
      p.maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      c.drawCircle(center, r * .51, p);
      p.maskFilter = null;
      p.color = Colors.white;
      p.shader = const LinearGradient(
              colors: [Stitch.cyan, Color(0xFF5B8CFF), Stitch.blue])
          .createShader(Offset.zero & s);
      c.drawCircle(center, r * .51, p);
      p.shader = null;
      p.color = const Color(0xFF23304D);
      c.drawCircle(center, r * .37, p);
      p.color = Stitch.cyan;
      for (int y = -2; y <= 2; y++)
        for (int x = -2; x <= 2; x++)
          if (x * x + y * y <= 5)
            c.drawCircle(
                center + Offset(x * r * .055, y * r * .055), r * .012, p);
      p.color = Stitch.cyan;
      c.drawCircle(center + Offset(r * .65, -r * .73), r * .025, p);
      p.color = Stitch.blue;
      c.drawCircle(center + Offset(-r * .61, r * .74), r * .03, p);
    }
  }

  @override
  bool shouldRepaint(OrbPainter old) => old.voice != voice;
}

class StitchHeader extends StatelessWidget implements PreferredSizeWidget {
  const StitchHeader(
      {super.key,
      required this.title,
      this.onVoice,
      this.onSettings,
      this.back = false});
  final String title;
  final VoidCallback? onVoice, onSettings;
  final bool back;
  @override
  Size get preferredSize => const Size.fromHeight(64);
  @override
  Widget build(BuildContext context) => AppBar(
          automaticallyImplyLeading: back,
          titleSpacing: 20,
          title: Row(children: [
            const CoreLogo(),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title, style: Stitch.title(21)),
                  Text('FRIDAY ASSISTANT', style: Stitch.mono(10, Stitch.cyan))
                ]))
          ]),
          actions: [
            if (onVoice != null)
              IconButton(
                  tooltip: 'Voice session',
                  onPressed: onVoice,
                  icon: const Icon(Icons.graphic_eq, color: Stitch.cyan)),
            if (onSettings != null)
              IconButton(
                  tooltip: 'Settings',
                  onPressed: onSettings,
                  icon: const Icon(Icons.account_circle_outlined)),
            const SizedBox(width: 8)
          ]);
}

class StitchBadge extends StatelessWidget {
  const StitchBadge(this.text, {super.key, this.color = Stitch.cyan});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: Stitch.high, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: Stitch.mono(10, color)));
}
