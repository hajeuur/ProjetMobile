import 'package:flutter/material.dart';

import '../logic/heartbeat.dart';

/// Couleur du cœur : vert (calme, lent), orange (rapide), rouge (affolé).
Color heartColor(HeartLevel level) => switch (level) {
      HeartLevel.calm || HeartLevel.slow => Colors.green.shade600,
      HeartLevel.fast => Colors.orange.shade700,
      HeartLevel.panic => Colors.red.shade600,
    };

/// Cœur qui bat en même temps que la vibration : il se gonfle à chaque
/// « tou » et « toum » du motif ([heartPulseAt]). Un nouveau [pattern]
/// (autre instance) relance l'animation ; sans motif, le cœur est immobile.
class BeatingHeart extends StatefulWidget {
  const BeatingHeart({super.key, required this.level, this.pattern, this.size = 40});
  final HeartLevel level;
  final HeartbeatPattern? pattern;
  final double size;

  @override
  State<BeatingHeart> createState() => _BeatingHeartState();
}

class _BeatingHeartState extends State<BeatingHeart> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _play();
  }

  @override
  void didUpdateWidget(BeatingHeart old) {
    super.didUpdateWidget(old);
    if (!identical(old.pattern, widget.pattern)) _play();
  }

  void _play() {
    final p = widget.pattern;
    if (p == null || p.isEmpty) {
      _c.stop();
      _c.value = 0;
      return;
    }
    _c.duration = p.total;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final p = widget.pattern;
          final pulse = p == null || p.isEmpty || !_c.isAnimating
              ? 0.0
              : heartPulseAt(p, Duration(milliseconds: (_c.value * p.total.inMilliseconds).round()));
          return SizedBox(
            width: widget.size * 1.4,
            height: widget.size * 1.4,
            child: Center(
              child: Transform.scale(
                scale: 1 + 0.35 * pulse,
                child: TweenAnimationBuilder<Color?>(
                  // La couleur glisse doucement quand le niveau change.
                  tween: ColorTween(end: heartColor(widget.level)),
                  duration: const Duration(milliseconds: 500),
                  builder: (_, color, _) => Icon(
                    Icons.favorite,
                    size: widget.size,
                    color: color,
                    semanticLabel: widget.level.label,
                  ),
                ),
              ),
            ),
          );
        },
      );
}
