import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/budget_forecast.dart';
import '../services/shopping_devices.dart';
import '../services/shopping_service.dart';
import '../viewmodels/budget_alert_center.dart';
import 'beating_heart.dart';
import '../shopping_module.dart';
import 'budget_screen.dart' show BudgetGauge;
import 'report_preview_screen.dart';

/// Place la bannière d'alerte de budget au-dessus de tous les écrans
/// (à brancher dans `MaterialApp.builder`).
class BudgetAlertOverlay extends StatelessWidget {
  const BudgetAlertOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final center = context.watch<BudgetAlertCenter>();
    final alert = center.current;
    return Stack(children: [
      child,
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, a) => SlideTransition(
              position: Tween(begin: const Offset(0, -1.2), end: Offset.zero)
                  .animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
              child: child,
            ),
            child: alert == null
                ? (center.heartNotice == null
                    ? const SizedBox.shrink()
                    : _HeartPill(key: ValueKey(center.heartNotice), notice: center.heartNotice!, onClose: center.dismissHeart))
                : BudgetAlertBanner(
                    key: ValueKey(alert),
                    alert: alert,
                    vibrating: center.vibrating,
                    onClose: center.dismiss,
                  ),
          ),
        ),
      ),
    ]);
  }
}

/// Bannière : jauge qui s'anime vers l'orange (ou le rouge), titre,
/// phrase intelligente et animation de vibration.
class BudgetAlertBanner extends StatelessWidget {
  const BudgetAlertBanner({super.key, required this.alert, required this.vibrating, required this.onClose});
  final BudgetAlert alert;
  final bool vibrating;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = alert.snapshot;
    final threshold = (s.budget?.alertThreshold ?? 80) / 100;
    final red = alert.level == BudgetLevel.exceeded;
    final color = red ? Colors.red.shade700 : Colors.orange.shade800;
    final n = alert.notice;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        color: Color.alphaBlend(color.withValues(alpha: 0.12), Theme.of(context).colorScheme.surface),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color, width: 2),
          ),
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            BudgetGauge(
              ratio: s.ratio,
              from: n.previousRatio ?? 0,
              threshold: threshold,
              size: 64,
              label: '',
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(alert.title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
                const SizedBox(height: 2),
                Text(alert.usage, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(alert.sentence, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                _VibrationStatus(vibrating: vibrating, notice: n, color: color),
                if (alert.report != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        final r = alert.report!;
                        onClose();
                        ShoppingModule.navigatorKey.currentState?.push(MaterialPageRoute<bool>(
                          builder: (_) => ReportPreviewScreen(
                            month: alert.snapshot.month,
                            reason: r.reason,
                            contact: r.contact,
                          ),
                        ));
                      },
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: Text('Envoyer le rapport à ${alert.report!.contact.firstName}'),
                    ),
                  ),
              ]),
            ),
            // Pas d'infobulle : la bannière est au-dessus du Navigator (pas d'Overlay).
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, semanticLabel: 'Fermer l\'alerte'),
              onPressed: onClose,
            ),
          ]),
        ),
      ),
    );
  }
}

/// Téléphone qui tremble avec des ondes pendant la vibration : visible même
/// sur un émulateur (qui ne vibre pas).
class _VibrationStatus extends StatelessWidget {
  const _VibrationStatus({required this.vibrating, required this.notice, required this.color});
  final bool vibrating;
  final BudgetNotice notice;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final beat = notice.heartbeat;
    if (vibrating && beat != null) {
      return Row(children: [
        BeatingHeart(level: beat.level, pattern: beat, size: 20),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '${beat.level.label}…${notice.vibrated ? '' : ' (simulé : pas de vibreur)'}',
            maxLines: 2,
            style: TextStyle(color: heartColor(beat.level), fontStyle: FontStyle.italic),
          ),
        ),
      ]);
    }
    if (vibrating) {
      return Row(children: [
        _ShakingPhone(color: color, duration: vibrationDuration(notice.snapshot.level)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '${notice.snapshot.level == BudgetLevel.exceeded ? 'Vibration longue…' : 'Vibration courte…'}'
            '${notice.vibrated ? '' : ' (simulée : pas de vibreur)'}',
            maxLines: 2,
            style: TextStyle(color: color, fontStyle: FontStyle.italic),
          ),
        ),
      ]);
    }
    final String? note = notice.vibrated
        ? null
        : !notice.vibrationEnabled
            ? 'Vibreur désactivé dans les Réglages'
            : notice.isNewLevel
                ? 'Pas de vibreur sur cet appareil : alerte visuelle'
                : null;
    if (note == null) return const SizedBox.shrink();
    return Row(children: [
      Icon(Icons.vibration, size: 16, color: Theme.of(context).colorScheme.outline),
      const SizedBox(width: 6),
      Flexible(child: Text(note, style: Theme.of(context).textTheme.bodySmall)),
    ]);
  }
}

/// Palier de 50 % : petite pastille avec le cœur qui bat (pas d'alerte).
class _HeartPill extends StatelessWidget {
  const _HeartPill({super.key, required this.notice, required this.onClose});
  final BudgetNotice notice;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final beat = notice.heartbeat!;
    final color = heartColor(beat.level);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(30),
          color: Color.alphaBlend(color.withValues(alpha: 0.12), Theme.of(context).colorScheme.surface),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 2, 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              BeatingHeart(level: beat.level, pattern: beat, size: 22),
              Text(
                'Budget à ${(notice.snapshot.ratio * 100).round()} % · ${beat.level.label.toLowerCase()}',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18, semanticLabel: 'Fermer'),
                onPressed: onClose,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ShakingPhone extends StatefulWidget {
  const _ShakingPhone({required this.color, required this.duration});
  final Color color;

  /// Durée du motif de vibration : l'animation s'arrête avec elle.
  final Duration duration;

  @override
  State<_ShakingPhone> createState() => _ShakingPhoneState();
}

class _ShakingPhoneState extends State<_ShakingPhone> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.duration)..forward();

  /// Nombre de secousses sur la durée du motif (~4 par seconde).
  double get _cycles => math.max(1, widget.duration.inMilliseconds / 260);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = _c.value * _cycles;
          return SizedBox(
            width: 40,
            height: 28,
            child: Stack(alignment: Alignment.center, children: [
              // Ondes de part et d'autre du téléphone.
              for (final side in [-1.0, 1.0])
                Positioned(
                  left: side < 0 ? 0 : null,
                  right: side > 0 ? 0 : null,
                  child: Opacity(
                    opacity: 0.3 + 0.7 * (0.5 + 0.5 * math.sin(2 * math.pi * t)),
                    child: Text(side < 0 ? '((' : '))', style: TextStyle(color: widget.color, fontWeight: FontWeight.bold)),
                  ),
                ),
              Transform.translate(
                offset: Offset(2.5 * math.sin(2 * math.pi * t * 2), 0),
                child: Transform.rotate(
                  angle: 0.18 * math.sin(2 * math.pi * t),
                  child: Icon(Icons.smartphone, color: widget.color, size: 22),
                ),
              ),
            ]),
          );
        },
      );
}
