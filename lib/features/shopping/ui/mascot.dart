import 'dart:math' as math;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/mascot_messages.dart';
import '../services/shopping_service.dart';

/// Traits du visage, interpolables d'une humeur à l'autre.
class _Face {
  const _Face({
    required this.smile,
    required this.brow,
    required this.eyeOpen,
    required this.sweat,
    required this.sparkle,
    required this.color,
  });

  /// -1 (bouche triste / ouverte) à 1 (grand sourire).
  final double smile;

  /// 0 (sourcils neutres) à 1 (très inquiets).
  final double brow;

  /// Ouverture des yeux (petite : yeux plissés de fierté).
  final double eyeOpen;
  final double sweat;
  final double sparkle;
  final Color color;

  static _Face of(MascotMood m) => switch (m) {
        MascotMood.happy =>
          const _Face(smile: 0.9, brow: 0, eyeOpen: 1, sweat: 0, sparkle: 0, color: Color(0xFFE53935)),
        MascotMood.calm =>
          const _Face(smile: 0.45, brow: 0.1, eyeOpen: 0.8, sweat: 0, sparkle: 0, color: Color(0xFFE53935)),
        MascotMood.worried =>
          const _Face(smile: -0.35, brow: 0.7, eyeOpen: 1.1, sweat: 0.3, sparkle: 0, color: Color(0xFFEF6C00)),
        MascotMood.panicked =>
          const _Face(smile: -1, brow: 1, eyeOpen: 1.35, sweat: 1, sparkle: 0, color: Color(0xFFC62828)),
        MascotMood.proud =>
          const _Face(smile: 1, brow: 0, eyeOpen: 0.2, sweat: 0, sparkle: 1, color: Color(0xFFE53935)),
      };

  static _Face lerp(_Face a, _Face b, double t) {
    double l(double x, double y) => x + (y - x) * t;
    return _Face(
      smile: l(a.smile, b.smile),
      brow: l(a.brow, b.brow),
      eyeOpen: l(a.eyeOpen, b.eyeOpen),
      sweat: l(a.sweat, b.sweat),
      sparkle: l(a.sparkle, b.sparkle),
      color: Color.lerp(a.color, b.color, t)!,
    );
  }
}

/// « Malin », la tomate mascotte. Le visage glisse doucement d'une humeur à
/// l'autre et rebondit une fois quand l'humeur change (pas d'animation en
/// boucle).
class MalinMascot extends StatefulWidget {
  const MalinMascot({super.key, required this.mood, this.size = 64});
  final MascotMood mood;
  final double size;

  @override
  State<MalinMascot> createState() => _MalinMascotState();
}

class _MalinMascotState extends State<MalinMascot> {
  late _Face _from = _Face.of(widget.mood);

  @override
  void didUpdateWidget(MalinMascot old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) _from = _Face.of(old.mood);
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Malin, la mascotte, ${widget.mood.label}',
        child: TweenAnimationBuilder<double>(
          key: ValueKey(widget.mood), // rebond à chaque changement d'humeur
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutBack,
          builder: (_, t, _) {
            final face = _Face.lerp(_from, _Face.of(widget.mood), t.clamp(0.0, 1.0));
            final bounce = 1 + 0.08 * math.sin(math.pi * t.clamp(0.0, 1.0));
            return Transform.scale(
              scale: bounce,
              child: CustomPaint(size: Size.square(widget.size), painter: _TomatoPainter(face)),
            );
          },
        ),
      );
}

class _TomatoPainter extends CustomPainter {
  _TomatoPainter(this.f);
  final _Face f;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final c = Offset(w / 2, w * 0.56);
    final r = w * 0.4;

    // Corps (légèrement aplati) et reflet.
    final body = Rect.fromCenter(center: c, width: r * 2.1, height: r * 1.9);
    canvas.drawOval(body, Paint()..color = f.color);
    canvas.drawOval(
      Rect.fromCenter(center: c + Offset(-r * 0.45, -r * 0.45), width: r * 0.5, height: r * 0.3),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );

    // Feuilles et tige.
    final leaf = Paint()..color = const Color(0xFF2E7D32);
    final top = Offset(w / 2, c.dy - r * 0.92);
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + (i - 2) * 0.55;
      final p = Path()
        ..moveTo(top.dx, top.dy)
        ..quadraticBezierTo(
          top.dx + math.cos(a - 0.3) * r * 0.35,
          top.dy + math.sin(a - 0.3) * r * 0.35,
          top.dx + math.cos(a) * r * 0.5,
          top.dy + math.sin(a) * r * 0.5 + r * 0.25,
        )
        ..quadraticBezierTo(top.dx + math.cos(a + 0.3) * r * 0.35, top.dy + math.sin(a + 0.3) * r * 0.35, top.dx, top.dy);
      canvas.drawPath(p, leaf);
    }
    canvas.drawLine(top, top + Offset(0, -r * 0.25), leaf..strokeWidth = w * 0.05);

    // Yeux.
    final eyeY = c.dy - r * 0.12;
    final dark = Paint()..color = const Color(0xFF3E2723);
    for (final dx in [-r * 0.38, r * 0.38]) {
      final e = Offset(c.dx + dx, eyeY);
      if (f.eyeOpen < 0.4) {
        // Yeux plissés de fierté : petits arcs.
        canvas.drawArc(
          Rect.fromCenter(center: e, width: r * 0.32, height: r * 0.26),
          math.pi,
          math.pi,
          false,
          dark
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.035
            ..strokeCap = StrokeCap.round,
        );
        dark.style = PaintingStyle.fill;
      } else {
        canvas.drawOval(Rect.fromCenter(center: e, width: r * 0.32, height: r * 0.34 * f.eyeOpen), Paint()..color = Colors.white);
        canvas.drawCircle(e + Offset(0, r * 0.02), r * 0.09 * (0.8 + 0.2 * f.eyeOpen), dark);
      }
      // Sourcils : relevés vers le centre quand on s'inquiète.
      final inner = dx < 0 ? 1 : -1;
      canvas.drawLine(
        e + Offset(-r * 0.15 * inner, -r * 0.27 + f.brow * r * 0.1),
        e + Offset(r * 0.15 * inner, -r * 0.27 - f.brow * r * 0.12),
        Paint()
          ..color = const Color(0xFF3E2723)
          ..strokeWidth = w * 0.03
          ..strokeCap = StrokeCap.round,
      );
    }

    // Joues roses quand on sourit.
    if (f.smile > 0) {
      final cheek = Paint()..color = Colors.pink.shade100.withValues(alpha: 0.7 * f.smile);
      canvas.drawCircle(Offset(c.dx - r * 0.62, c.dy + r * 0.18), r * 0.13, cheek);
      canvas.drawCircle(Offset(c.dx + r * 0.62, c.dy + r * 0.18), r * 0.13, cheek);
    }

    // Bouche : sourire, moue, ou bouche ouverte (panique).
    final mouthY = c.dy + r * 0.32;
    if (f.smile < -0.7) {
      canvas.drawOval(Rect.fromCenter(center: Offset(c.dx, mouthY + r * 0.04), width: r * 0.28, height: r * 0.34), dark);
    } else {
      final p = Path()
        ..moveTo(c.dx - r * 0.3, mouthY)
        ..quadraticBezierTo(c.dx, mouthY + f.smile * r * 0.4, c.dx + r * 0.3, mouthY);
      canvas.drawPath(
        p,
        Paint()
          ..color = const Color(0xFF3E2723)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.04
          ..strokeCap = StrokeCap.round,
      );
    }

    // Goutte de sueur (inquiet, paniqué).
    if (f.sweat > 0.05) {
      final d = Offset(c.dx + r * 0.95, c.dy - r * 0.35);
      final drop = Path()
        ..moveTo(d.dx, d.dy - r * 0.22)
        ..quadraticBezierTo(d.dx + r * 0.16, d.dy, d.dx, d.dy + r * 0.06)
        ..quadraticBezierTo(d.dx - r * 0.16, d.dy, d.dx, d.dy - r * 0.22);
      canvas.drawPath(drop, Paint()..color = Colors.lightBlue.shade300.withValues(alpha: f.sweat.clamp(0.0, 1.0)));
    }

    // Étincelles (fier).
    if (f.sparkle > 0.05) {
      final s = Paint()..color = Colors.amber.withValues(alpha: f.sparkle.clamp(0.0, 1.0));
      for (final o in [Offset(-r * 1.05, -r * 0.7), Offset(r * 1.0, -r * 0.85), Offset(r * 1.1, r * 0.2)]) {
        _star(canvas, c + o, r * 0.13, s);
      }
    }
  }

  void _star(Canvas canvas, Offset c, double r, Paint p) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final rr = i.isEven ? r : r * 0.4;
      final a = i * math.pi / 4 - math.pi / 2;
      final pt = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(path..close(), p);
  }

  @override
  bool shouldRepaint(_TomatoPainter old) => true;
}

/// Mascotte et sa bulle de dialogue.
class MascotCard extends StatelessWidget {
  const MascotCard({super.key, required this.mood, required this.text, this.size = 64});
  final MascotMood mood;
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      MalinMascot(mood: mood, size: size),
      const SizedBox(width: 8),
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Container(
            key: ValueKey(text),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Text(text, style: theme.textTheme.bodyMedium),
          ),
        ),
      ),
    ]);
  }
}

/// Bulle de la mascotte sur l'accueil Courses et l'écran Budget : dernier
/// commentaire de ticket, sinon message d'accueil selon l'humeur du mois.
/// Se met à jour à chaque ticket ; rien si la mascotte est désactivée.
class MascotBubble extends StatefulWidget {
  const MascotBubble({super.key});

  @override
  State<MascotBubble> createState() => _MascotBubbleState();
}

class _MascotBubbleState extends State<MascotBubble> {
  late final ShoppingService _service = context.read<ShoppingService>();
  ({MascotMood mood, String text})? _bubble;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _service.receiptsChanged.listen((_) => _load());
  }

  Future<void> _load() async {
    final b = await _service.mascotBubble();
    if (mounted) setState(() => _bubble = b);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = _bubble;
    if (b == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MascotCard(mood: b.mood, text: b.text),
    );
  }
}
