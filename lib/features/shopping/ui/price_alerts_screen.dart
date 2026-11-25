import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/price_alerts.dart';
import '../models/dates.dart';
import '../services/product_scan_service.dart';
import '../services/shopping_service.dart';
import '../viewmodels/budget_view_model.dart';
import 'best_time_screen.dart';
import 'habitual_basket_screen.dart';
import 'product_sheet_screen.dart';
import 'store_comparison_screen.dart';
import 'widgets.dart';

/// Écran « Alertes de prix » : produits dont le dernier prix dépasse de plus
/// de 10 % la moyenne des trois mois précédents.
class PriceAlertsScreen extends StatelessWidget {
  const PriceAlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PriceAlertsViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alertes de prix'),
        actions: [
          IconButton(
            tooltip: 'Comparer les magasins',
            icon: const Icon(Icons.compare_arrows),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StoreComparisonScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'scan_product',
        onPressed: () => scanProduct(context),
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scanner un produit'),
      ),
      body: RefreshIndicator(
        onRefresh: vm.load,
        child: vm.loading && vm.alerts.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
                const HabitualBasketCard(),
                const BestTimeCard(),
                const _WatchedProducts(),
                if (vm.error != null)
                  EmptyState(icon: Icons.error_outline, title: vm.error!)
                else if (vm.alerts.isEmpty)
                  const EmptyState(
                    icon: Icons.trending_flat,
                    title: 'Aucune hausse de prix',
                    message: 'Une alerte apparaît quand un produit coûte plus de 10 % de plus '
                        'que sa moyenne des trois derniers mois.',
                  )
                else ...[
                  Text(
                    'Dernier prix payé comparé à la moyenne des 3 mois précédents (seuil +10 %).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  for (final a in vm.alerts) _AlertTile(alert: a),
                ],
              ]),
      ),
    );
  }
}

/// Produits surveillés depuis la fiche produit (scan de code-barres).
class _WatchedProducts extends StatefulWidget {
  const _WatchedProducts();

  @override
  State<_WatchedProducts> createState() => _WatchedProductsState();
}

class _WatchedProductsState extends State<_WatchedProducts> {
  late Future<List<WatchedProduct>> _future = context.read<ProductScanService>().watched();

  void _reload() => setState(() => _future = context.read<ProductScanService>().watched());

  @override
  Widget build(BuildContext context) => FutureBuilder<List<WatchedProduct>>(
        future: _future,
        builder: (context, snap) {
          final list = snap.data ?? const [];
          if (list.isEmpty) return const SizedBox.shrink();
          return Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const ListTile(
                leading: Icon(Icons.notifications_active_outlined),
                title: Text('Produits surveillés'),
              ),
              for (final w in list)
                ListTile(
                  dense: true,
                  title: Text(w.name),
                  subtitle: Text(w.mean == null
                      ? 'Code ${w.code}'
                      : 'Moyenne communauté au ${formatDate(w.since)} : ${formatDt(w.mean!)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductSheetScreen(code: w.code)));
                    _reload();
                  },
                ),
            ]),
          );
        },
      );
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});
  final PriceAlert alert;

  static final _compact = TextButton.styleFrom(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 8),
  );

  @override
  Widget build(BuildContext context) {
    final a = alert;
    final strong = a.increase >= 0.2;
    final c = strong ? Colors.red.shade600 : Colors.orange.shade800;
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showHistory(context, a),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(backgroundColor: c.withValues(alpha: 0.15), child: Icon(Icons.trending_up, color: c)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.label, style: theme.textTheme.titleMedium),
                  Text('${formatDt(a.lastPrice)} au lieu de ${formatDt(a.average)} en moyenne'),
                  Text(
                    '${formatDate(a.lastDate)}${a.storeName == null ? '' : ' · ${a.storeName}'} · '
                    'basé sur ${plural(a.sampleCount, 'achat')}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  ReliabilityChip(a.reliability),
                ]),
              ),
              Text(formatPct(a.increase), style: theme.textTheme.titleMedium?.copyWith(color: c, fontWeight: FontWeight.bold)),
            ]),
            // Alerte intelligente : que faire de cette hausse ?
            Wrap(spacing: 0, runSpacing: 0, children: [
              TextButton.icon(
                style: _compact,
                onPressed: () => _whereCheaper(context, a),
                icon: const Icon(Icons.compare_arrows, size: 18),
                label: const Text('Où le payer moins cher ?'),
              ),
              TextButton.icon(
                style: _compact,
                onPressed: () async {
                  final n = await context.read<PriceAlertsViewModel>().addToList(a);
                  if (context.mounted) {
                    showSnack(context, n == 0 ? 'Déjà dans la liste en cours.' : 'Ajouté à la liste en cours.');
                  }
                },
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: const Text('Ajouter à ma liste'),
              ),
              TextButton.icon(
                style: _compact,
                onPressed: () => _showHistory(context, a),
                icon: const Icon(Icons.show_chart, size: 18),
                label: const Text('Évolution'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _whereCheaper(BuildContext context, PriceAlert a) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => StoreComparisonScreen(focusKey: a.key)));

  Future<void> _showHistory(BuildContext context, PriceAlert a) {
    final service = context.read<ShoppingService>();
    return showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 24, 16),
          child: FutureBuilder<List<PricePoint>>(
            future: service.priceHistory(a.key),
            builder: (c, snap) {
              final points = snap.data ?? const <PricePoint>[];
              return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Évolution du prix — ${a.label}', style: Theme.of(c).textTheme.titleMedium),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: points.length < 2
                      ? const Center(child: CircularProgressIndicator())
                      : _PriceLine(points: points, average: a.average),
                ),
                const SizedBox(height: 8),
                Text('Trait pointillé : moyenne des 3 mois précédents.', style: Theme.of(c).textTheme.bodySmall),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.points, required this.average});
  final List<PricePoint> points;
  final double average;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = points.first.date;
    double x(DateTime d) => d.difference(first).inHours / 24;
    final maxY = points.map((p) => p.unitPrice).reduce((a, b) => a > b ? a : b);
    final minY = points.map((p) => p.unitPrice).reduce((a, b) => a < b ? a : b);
    return LineChart(LineChartData(
      minY: (minY * 0.85).floorToDouble(),
      maxY: (maxY * 1.1).ceilToDouble(),
      gridData: const FlGridData(drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 30,
            getTitlesWidget: (value, meta) {
              final d = first.add(Duration(days: value.round()));
              return SideTitleWidget(meta: meta, child: Text(monthShort(d), style: const TextStyle(fontSize: 11)));
            },
          ),
        ),
      ),
      extraLinesData: ExtraLinesData(horizontalLines: [
        HorizontalLine(y: average, color: scheme.outline, strokeWidth: 1, dashArray: [6, 4]),
      ]),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => [
            for (final s in spots)
              LineTooltipItem(
                '${formatDt(points[s.spotIndex].unitPrice)}\n${points[s.spotIndex].storeName ?? ''}',
                TextStyle(color: scheme.onInverseSurface, fontSize: 12),
              ),
          ],
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [for (final p in points) FlSpot(x(p.date), p.unitPrice)],
          color: scheme.primary,
          barWidth: 3,
          dotData: const FlDotData(show: true),
        ),
      ],
    ));
  }
}

/// Pastille de fiabilité d'une alerte (nombre d'achats ayant servi à la moyenne).
class ReliabilityChip extends StatelessWidget {
  const ReliabilityChip(this.reliability, {super.key});
  final AlertReliability reliability;

  @override
  Widget build(BuildContext context) {
    final (color, bars) = switch (reliability) {
      AlertReliability.low => (Colors.grey.shade600, 1),
      AlertReliability.medium => (Colors.blue.shade700, 2),
      AlertReliability.high => (Colors.green.shade700, 3),
    };
    return Tooltip(
      message: reliability.explanation,
      triggerMode: TooltipTriggerMode.tap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 5,
            height: 6.0 + 3 * i,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: i < bars ? color : color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(reliability.label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}
