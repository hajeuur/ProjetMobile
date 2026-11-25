import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/best_time.dart';
import '../logic/price_alerts.dart' show AlertReliability;
import '../models/dates.dart';
import '../services/shopping_devices.dart';
import '../services/shopping_service.dart';
import 'price_alerts_screen.dart' show ReliabilityChip;
import 'widgets.dart';

/// Fiabilité selon le nombre d'achats analysés (6 au minimum).
AlertReliability bestTimeReliability(int purchases) => purchases < 8
    ? AlertReliability.low
    : purchases < 12
        ? AlertReliability.medium
        : AlertReliability.high;

/// Charge les analyses (et les recharge à chaque ticket), en respectant
/// l'interrupteur « Meilleur moment pour acheter ».
class _InsightsLoader extends StatefulWidget {
  const _InsightsLoader({required this.builder});
  final Widget Function(BuildContext context, List<BestTimeInsight> insights) builder;

  @override
  State<_InsightsLoader> createState() => _InsightsLoaderState();
}

class _InsightsLoaderState extends State<_InsightsLoader> {
  late final ShoppingService _service = context.read<ShoppingService>();
  List<BestTimeInsight>? _insights;
  bool _enabled = true;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _service.receiptsChanged.listen((_) => _load());
  }

  Future<void> _load() async {
    final enabled = (await _service.settings()).bestTime;
    final list = enabled ? await _service.bestTimes() : null;
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _insights = list;
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      !_enabled || _insights == null ? const SizedBox.shrink() : widget.builder(context, _insights!);
}

/// Section de l'écran Prix : les deux meilleures conclusions.
class BestTimeCard extends StatelessWidget {
  const BestTimeCard({super.key});

  @override
  Widget build(BuildContext context) => _InsightsLoader(
        builder: (context, all) {
          final found = all.where((i) => i.status == BestTimeStatus.ok).toList();
          final theme = Theme.of(context);
          return Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.event_available_outlined),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Meilleur moment pour acheter', style: theme.textTheme.titleMedium)),
                ]),
                const SizedBox(height: 6),
                if (found.isEmpty)
                  Text(
                    all.every((i) => i.status == BestTimeStatus.notEnoughData)
                        ? 'Il faut au moins 6 achats d\'un même produit pour repérer quand il est moins cher.'
                        : 'Pas encore d\'écart net (au moins 5 %) selon le moment, le jour ou le magasin.',
                    style: theme.textTheme.bodyMedium,
                  )
                else
                  for (final i in found.take(2))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.trending_down, color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${i.sentence}.')),
                      ]),
                    ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BestTimeScreen())),
                    icon: const Icon(Icons.insights),
                    label: Text(found.isEmpty ? 'Voir l\'analyse' : 'Voir le détail'),
                  ),
                ),
              ]),
            ),
          );
        },
      );
}

class BestTimeScreen extends StatelessWidget {
  const BestTimeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Meilleur moment pour acheter')),
        body: _InsightsLoader(
          builder: (context, all) {
            final theme = Theme.of(context);
            final found = all.where((i) => i.status == BestTimeStatus.ok).toList();
            final flat = all.where((i) => i.status == BestTimeStatus.noDifference).toList();
            final watching = all.where((i) => i.status == BestTimeStatus.notEnoughData).toList();
            if (all.isEmpty) {
              return const EmptyState(
                icon: Icons.event_available_outlined,
                title: 'Pas encore assez d\'achats',
                message: 'L\'analyse démarre quand un produit a été acheté au moins 6 fois '
                    '(moment du mois, jour de la semaine, magasin).',
              );
            }
            return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
              Text(
                'Prix moyen selon le moment du mois, le jour et le magasin. Conclusion seulement au-delà de 5 % '
                'd\'écart, avec au moins 6 achats.',
                style: theme.textTheme.bodySmall,
              ),
              for (final i in found) _InsightCard(insight: i),
              if (flat.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Prix stables', style: theme.textTheme.titleSmall),
                for (final i in flat)
                  Card(child: ListTile(dense: true, title: Text(i.sentence), subtitle: Text(i.basis))),
              ],
              if (watching.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('En observation', style: theme.textTheme.titleSmall),
                Card(
                  child: Column(children: [
                    for (final i in watching)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.hourglass_bottom),
                        title: Text(i.label),
                        subtitle: Text('${plural(i.purchases, 'achat')} sur $minPurchases nécessaires'),
                        trailing: SizedBox(
                          width: 60,
                          child: LinearProgressIndicator(value: i.purchases / minPurchases),
                        ),
                      ),
                  ]),
                ),
              ],
            ]);
          },
        ),
      );
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});
  final BestTimeInsight insight;

  Future<void> _remind(BuildContext context) async {
    final service = context.read<ShoppingService>();
    final at = nextReminder(insight, service.now);
    final ok = await context.read<LocalNotifier>().schedule(
          id: 7000 + insight.key.hashCode.abs() % 1000,
          title: 'PanierMalin · bon moment pour acheter',
          body: insight.reminderText,
          at: at,
        );
    if (!context.mounted) return;
    showSnack(
      context,
      ok
          ? 'Rappel prévu le ${formatDate(at)} à ${at.hour} h.'
          : 'Rappel impossible : autorisez les notifications de PanierMalin dans les réglages du téléphone.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final i = insight;
    final theme = Theme.of(context);
    final green = Colors.green.shade700;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.trending_down, color: green),
            const SizedBox(width: 8),
            Expanded(child: Text('${i.sentence}.', style: theme.textTheme.titleSmall)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(i.basis, style: theme.textTheme.bodySmall),
            ReliabilityChip(bestTimeReliability(i.purchases)),
          ]),
          const SizedBox(height: 8),
          for (final d in i.dimensions.take(2)) _MiniChart(result: d),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _remind(context),
              icon: const Icon(Icons.alarm_add),
              label: const Text('Me rappeler'),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Prix moyen par groupe (barres), le meilleur en vert.
class _MiniChart extends StatelessWidget {
  const _MiniChart({required this.result});
  final DimensionResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = result.groups.map((g) => g.mean).reduce((a, b) => a > b ? a : b);
    final min = result.groups.map((g) => g.mean).reduce((a, b) => a < b ? a : b);
    final title = switch (result.dimension) {
      Dimension.monthPart => 'Selon le moment du mois',
      Dimension.weekday => 'Selon le jour',
      Dimension.store => 'Selon le magasin',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$title · -${(result.saving * 100).round()} %', style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        SizedBox(
          height: 112,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final g in result.groups)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text(
                      g.mean.toStringAsFixed(2).replaceAll('.', ','),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: g == result.best ? FontWeight.bold : null,
                        color: g == result.best ? Colors.green.shade700 : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      // Hauteur relative : l'écart reste lisible même s'il est petit.
                      builder: (_, t, _) => Container(
                        height: t * (18 + 36 * (max == min ? 1 : (g.mean - min) / (max - min) + 0.2)),
                        decoration: BoxDecoration(
                          color: g == result.best ? Colors.green.shade600 : theme.colorScheme.outline,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(g.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
