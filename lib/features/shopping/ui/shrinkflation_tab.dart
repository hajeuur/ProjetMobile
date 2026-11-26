import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/pack_format.dart';
import '../logic/shrinkflation.dart';
import '../models/dates.dart';
import '../services/shopping_service.dart';
import 'widgets.dart';

/// Onglet « Shrinkflation » des alertes de prix : cartes avant / après, et
/// formats illisibles à confirmer.
class ShrinkflationTab extends StatefulWidget {
  const ShrinkflationTab({super.key});

  @override
  State<ShrinkflationTab> createState() => _ShrinkflationTabState();
}

class _ShrinkflationTabState extends State<ShrinkflationTab> {
  late final ShoppingService _service = context.read<ShoppingService>();
  ({List<ShrinkAlert> alerts, List<FormatToConfirm> toConfirm})? _data;
  bool _enabled = true;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _service.receiptsChanged.listen((_) => _load());
  }

  Future<void> _load() async {
    final enabled = (await _service.settings()).shrinkflation;
    final data = enabled ? await _service.shrinkflation() : null;
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _data = data;
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _confirm(FormatToConfirm c, PackFormat? f) async {
    await _service.confirmPackFormat(c.purchase.lineId!, f);
    await _load();
    if (mounted) showSnack(context, f == null ? 'Noté : format inconnu.' : 'Format enregistré : ${f.label}.');
  }

  Future<void> _other(FormatToConfirm c) async {
    final v = await promptText(
      context,
      title: 'Format de « ${c.name} »',
      label: 'Par exemple 200 g, 1 L, 6 x 33 cl',
    );
    if (v == null || !mounted) return;
    final f = parsePackFormat(v);
    if (f == null) {
      showSnack(context, 'Format non reconnu. Exemples : 250 g, 1,5 L, 50 cl, 4 x 125 g.');
      return;
    }
    await _confirm(c, f);
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) {
      return const EmptyState(
        icon: Icons.compress,
        title: 'Détecteur désactivé',
        message: 'Activez « Détecteur de shrinkflation » dans les Réglages.',
      );
    }
    final d = _data;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
        Text(
          'Même produit, format plus petit, prix identique ou en hausse : le prix au kilo (ou au litre) '
          'augmente sans que l\'étiquette change.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (d.alerts.isEmpty)
          const EmptyState(
            icon: Icons.verified_outlined,
            title: 'Aucune shrinkflation détectée',
            message: 'Le format est lu dans les libellés des tickets (250G, 1L, 6X1,5L…).',
          ),
        for (final a in d.alerts) _ShrinkCard(alert: a),
        if (d.toConfirm.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Formats à confirmer', style: theme.textTheme.titleSmall),
          Text(
            'Le ticket n\'indique pas le format : impossible de comparer sans vous.',
            style: theme.textTheme.bodySmall,
          ),
          for (final c in d.toConfirm)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('« ${c.purchase.label} » du ${formatDate(c.purchase.date)} : quel format ?'),
                  Wrap(spacing: 8, children: [
                    FilledButton.tonal(
                      onPressed: () => _confirm(c, c.known),
                      child: Text('${c.known.label}, comme d\'habitude'),
                    ),
                    TextButton(onPressed: () => _other(c), child: const Text('Autre format')),
                    TextButton(onPressed: () => _confirm(c, null), child: const Text('Je ne sais pas')),
                  ]),
                ]),
              ),
            ),
        ],
      ]),
    );
  }
}

/// Carte avant / après : format, prix payé, prix au kilo / au litre.
class _ShrinkCard extends StatelessWidget {
  const _ShrinkCard({required this.alert});
  final ShrinkAlert alert;

  @override
  Widget build(BuildContext context) {
    final a = alert;
    final red = Colors.red.shade700;
    final theme = Theme.of(context);
    final unit = a.after.format!.measure.big;
    final title = a.name.isEmpty ? a.after.label : a.name[0].toUpperCase() + a.name.substring(1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.compress, color: red),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: red.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Text(
                '+${(a.perBigIncrease * 100).round()} % au $unit'.replaceAll('au L', 'au litre').replaceAll('au kg', 'au kilo'),
                style: TextStyle(color: red, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(a.sentence, style: TextStyle(color: red, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _Side(title: 'Avant', p: a.before)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward, color: theme.colorScheme.outline),
              ),
              Expanded(child: _Side(title: 'Après', p: a.after, highlight: true)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.title, required this.p, this.highlight = false});
  final String title;
  final PackPurchase p;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = p.format!;
    final color = highlight ? Colors.red.shade700 : null;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: highlight ? Border.all(color: Colors.red.shade300) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: theme.textTheme.labelLarge),
        Text(formatDate(p.date), style: theme.textTheme.bodySmall),
        if (p.store != null) Text(p.store!, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Text(f.label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(formatDt(p.price)),
        Text(
          '${formatDt(p.pricePerBig!)}/${f.measure.big}',
          style: TextStyle(fontWeight: FontWeight.w600, color: color),
        ),
      ]),
    );
  }
}
