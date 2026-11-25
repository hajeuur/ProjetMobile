import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/advice.dart';
import '../logic/badges.dart';
import '../logic/budget_forecast.dart';
import '../models/dates.dart';
import '../services/shopping_devices.dart';
import '../services/shopping_service.dart';
import '../viewmodels/budget_view_model.dart';
import 'widgets.dart';

/// Écran « Budget du mois » : jauge, prévision de fin de mois, conseil du
/// jour, statistiques et badges.
class BudgetScreen extends StatelessWidget {
  const BudgetScreen({super.key});

  Future<void> _edit(BuildContext context) async {
    final vm = context.read<BudgetViewModel>();
    final b = vm.snapshot?.budget;
    final r = await showDialog<(double, int)>(
      context: context,
      builder: (_) => _BudgetDialog(month: vm.month, amount: b?.amount, threshold: b?.alertThreshold ?? 80),
    );
    if (r == null || !context.mounted) return;
    try {
      await vm.setBudget(r.$1, r.$2);
      // Pour être prévenu même app en arrière-plan : autorisation des notifications.
      if (context.mounted) await context.read<LocalNotifier>().requestPermission();
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BudgetViewModel>();
    final s = vm.snapshot;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget'),
        actions: [
          IconButton(tooltip: 'Définir le budget', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(context)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: vm.load,
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
          Row(children: [
            IconButton(onPressed: () => vm.goToMonth(-1), icon: const Icon(Icons.chevron_left), tooltip: 'Mois précédent'),
            Expanded(
              child: TextButton(
                onPressed: vm.isCurrentMonth ? null : () => vm.goToMonth(0),
                child: Text(monthTitle(vm.month), style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            IconButton(
              onPressed: vm.isCurrentMonth ? null : () => vm.goToMonth(1),
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Mois suivant',
            ),
          ]),
          if (vm.error != null) EmptyState(icon: Icons.error_outline, title: vm.error!),
          if (s == null && vm.loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          if (s != null) ...[
            if (vm.isCurrentMonth && (s.level.index >= BudgetLevel.threshold.index || s.forecastOverrun))
              _AlertBanner(snapshot: s),
            _BudgetCard(snapshot: s, onEdit: () => _edit(context)),
            if (vm.isCurrentMonth && vm.advice != null && vm.advice!.message.isNotEmpty) _AdviceCard(vm.advice!),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: StatTile(
                  label: 'Panier moyen (3 mois)',
                  value: formatDt(vm.averageBasket),
                  icon: Icons.shopping_basket_outlined,
                ),
              ),
              Expanded(
                child: StatTile(
                  label: 'Budget respecté',
                  value: vm.respect.$2 == 0 ? '—' : '${vm.respect.$1} / ${vm.respect.$2} mois',
                  icon: Icons.verified_outlined,
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Text('Dépenses par mois', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const _ChartLegend(),
            const SizedBox(height: 8),
            SizedBox(height: 220, child: _MonthlyChart(vm.monthly)),
            const SizedBox(height: 20),
            Text('Dépenses par catégorie — ${monthLabel(vm.month)}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (vm.categories.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('Aucun achat ce mois-ci.'))
            else
              _CategoryChart(vm.categories),
            if (vm.badges.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Badges et défis', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _BadgesGrid(vm.badges),
            ],
          ],
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- Alerte

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({required this.snapshot});
  final BudgetSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final c = budgetColor(context, s.level, forecast: s.forecastOverrun);
    // Même calcul que la carte : « 86 % utilisé » et « seuil de 80 % franchi ».
    final text = BudgetNotice(snapshot: s, isNewLevel: false, isNewForecast: false).message;
    return Card(
      color: c.withValues(alpha: 0.12),
      child: ListTile(
        leading: Icon(s.level == BudgetLevel.exceeded ? Icons.error : Icons.warning_amber, color: c),
        title: Text(
          s.level == BudgetLevel.exceeded
              ? 'Budget dépassé'
              : s.level == BudgetLevel.threshold
                  ? 'Seuil d\'alerte franchi${s.forecastOverrun ? ' · dépassement prévu' : ''}'
                  : 'Dépassement prévu',
          style: TextStyle(fontWeight: FontWeight.bold, color: c),
        ),
        subtitle: Text(text),
      ),
    );
  }
}

// ---------------------------------------------------------- Carte + jauge

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.snapshot, required this.onEdit});
  final BudgetSnapshot snapshot;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final b = s.budget;
    final theme = Theme.of(context);
    if (b == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Text('Dépensé : ${formatDt(s.spent)}', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Aucun budget pour ce mois.'),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: onEdit, icon: const Icon(Icons.add), label: const Text('Définir un budget')),
          ]),
        ),
      );
    }
    final color = budgetColor(context, s.level, forecast: s.forecastOverrun);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            BudgetGauge(
              ratio: s.ratio,
              threshold: b.alertThreshold / 100,
              projected: b.amount == 0 ? 0 : s.projected / b.amount,
              size: 132,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(formatDt(s.spent), style: theme.textTheme.headlineSmall?.copyWith(color: color)),
                ),
                Text('sur ${formatDt(b.amount)}', style: theme.textTheme.bodyLarge),
                const SizedBox(height: 6),
                Text('Seuil d\'alerte : ${b.alertThreshold} %', style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                Text(s.level.label, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          // Phrase intelligente : « À ce rythme, tu dépasseras de 4,6 DT. Limite-toi à 3,9 DT/jour. »
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(Icons.lightbulb_outline, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(budgetSentence(s), style: TextStyle(color: color, fontWeight: FontWeight.w600))),
            ]),
          ),
          const Divider(height: 24),
          _row(context, Icons.savings_outlined, s.remaining >= 0 ? 'Reste' : 'Dépassement', formatDt(s.remaining.abs())),
          if (s.daysLeft > 0) ...[
            _row(context, Icons.trending_up, 'Prévision fin de mois', formatDt(s.projected),
                color: s.forecastOverrun || s.level == BudgetLevel.exceeded ? Colors.red.shade600 : Colors.green.shade700),
            if (s.dailyAllowance != null)
              _row(context, Icons.today, 'Possible par jour (${plural(s.daysLeft, 'jour')} restants)', formatDt(s.dailyAllowance!)),
          ],
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(value, textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
          ),
        ]),
      );
}

/// Jauge circulaire animée : elle se remplit du vert à l'orange (seuil) puis
/// au rouge (budget atteint). Un trait marque le seuil, un arc pâle la
/// prévision de fin de mois.
class BudgetGauge extends StatelessWidget {
  const BudgetGauge({
    super.key,
    required this.ratio,
    required this.threshold,
    this.from = 0,
    this.projected = 0,
    this.size = 140,
    this.label = 'utilisé',
  });
  final double ratio;
  final double threshold;

  /// Valeur de départ de l'animation (0 à l'ouverture, la dépense d'avant
  /// le ticket dans la bannière d'alerte).
  final double from;
  final double projected;
  final double size;
  final String label;

  static final _green = Colors.green.shade600;
  static final _orange = Colors.orange.shade700;
  static final _red = Colors.red.shade600;

  /// Vert sous le seuil, orange au seuil, rouge au budget complet, avec une
  /// transition douce juste avant chaque palier (la couleur glisse pendant
  /// que la jauge se remplit).
  static Color colorFor(double value, double threshold) {
    const blend = 0.06;
    if (value >= 1) return _red;
    if (value >= 1 - blend) return Color.lerp(_orange, _red, (value - (1 - blend)) / blend)!;
    if (value >= threshold) return _orange;
    if (value >= threshold - blend) return Color.lerp(_green, _orange, (value - (threshold - blend)) / blend)!;
    return _green;
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: from, end: ratio),
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) {
          final color = colorFor(value, threshold);
          return SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _GaugePainter(
                value: value,
                threshold: threshold,
                projected: projected,
                color: color,
                track: Theme.of(context).colorScheme.surfaceContainerHighest,
                tick: Theme.of(context).colorScheme.onSurface,
              ),
              child: Center(
                // Le pourcentage rétrécit dans une petite jauge (bannière d'alerte).
                child: Padding(
                  padding: EdgeInsets.all(size * 0.18),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        '${(value * 100).round()} %',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.bold),
                      ),
                      if (label.isNotEmpty) Text(label, style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.threshold,
    required this.projected,
    required this.color,
    required this.track,
    required this.tick,
  });

  final double value;
  final double threshold;
  final double projected;
  final Color color;
  final Color track;
  final Color tick;

  static const _start = math.pi * 0.75; // 135° : arc de 270° ouvert en bas
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(arc, _start, _sweep, false, p(track));
    if (projected > value) {
      canvas.drawArc(arc, _start, _sweep * projected.clamp(0, 1), false, p(color.withValues(alpha: 0.25)));
    }
    if (value > 0) canvas.drawArc(arc, _start, _sweep * value.clamp(0, 1), false, p(color));

    // Trait du seuil d'alerte.
    final angle = _start + _sweep * threshold.clamp(0, 1);
    final c = rect.center;
    final r = arc.width / 2;
    canvas.drawLine(
      c + Offset(math.cos(angle), math.sin(angle)) * (r - stroke * 0.9),
      c + Offset(math.cos(angle), math.sin(angle)) * (r + stroke * 0.9),
      Paint()
        ..color = tick
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color || old.projected != projected || old.threshold != threshold;
}

// --------------------------------------------------------- Conseil du jour

class _AdviceCard extends StatelessWidget {
  const _AdviceCard(this.advice);
  final Advice advice;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (advice.tone) {
      AdviceTone.good => (Icons.thumb_up_alt_outlined, Colors.green.shade700),
      AdviceTone.warning => (Icons.lightbulb_outline, Colors.orange.shade800),
      AdviceTone.danger => (Icons.report_gmailerrorred, Colors.red.shade600),
      AdviceTone.neutral => (Icons.tips_and_updates_outlined, Theme.of(context).colorScheme.primary),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Conseil du jour · ${advice.title}', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 4),
              Text(advice.message),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------ Dépenses par mois

class _ChartLegend extends StatelessWidget {
  const _ChartLegend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget item(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]);
    return Wrap(spacing: 14, runSpacing: 4, children: [
      item(scheme.primary, 'Dépensé'),
      item(Colors.red.shade400, 'Dépensé (budget dépassé)'),
      item(scheme.outlineVariant, 'Budget'),
    ]);
  }
}

class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart(this.months);
  final List<MonthSpending> months;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = months.fold<double>(0, (m, x) => math.max(m, math.max(x.spent, x.budget ?? 0)));
    final axis = niceAxis(top);
    return BarChart(
      BarChartData(
        maxY: axis.maxY,
        gridData: FlGridData(drawVerticalLine: false, horizontalInterval: axis.interval),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, rodIndex) {
              final m = months[group.x];
              return BarTooltipItem(
                '${monthShort(m.month)}\n${rodIndex == 0 ? 'Dépensé ${formatDt(m.spent)}' : 'Budget ${formatDt(m.budget ?? 0)}'}',
                TextStyle(color: scheme.onInverseSurface),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: axis.interval,
              getTitlesWidget: (value, meta) {
                // Uniquement les paliers ronds (0, 50, 100, 150).
                if (value % axis.interval != 0) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(value.toStringAsFixed(0), style: Theme.of(context).textTheme.bodySmall),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= months.length) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(monthShort(months[i].month), style: Theme.of(context).textTheme.bodySmall),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < months.length; i++)
            BarChartGroupData(x: i, barsSpace: 3, barRods: [
              BarChartRodData(
                toY: months[i].spent,
                width: 14,
                color: months[i].budget != null && months[i].spent > months[i].budget! ? Colors.red.shade400 : scheme.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
              BarChartRodData(
                toY: months[i].budget ?? 0,
                width: 8,
                color: scheme.outlineVariant,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------- Dépenses par catégorie

/// Les petites catégories sont regroupées dans « Autres » (au plus 4
/// catégories visibles, chacune ≥ 6 % du total).
List<MapEntry<String, double>> groupCategories(Map<String, double> data, {int maxSlices = 4, double minShare = 0.06}) {
  final entries = data.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
  final total = entries.fold<double>(0, (s, e) => s + e.value);
  final kept = <MapEntry<String, double>>[];
  var others = 0.0;
  for (final e in entries) {
    if (kept.length < maxSlices && total > 0 && e.value / total >= minShare) {
      kept.add(e);
    } else {
      others += e.value;
    }
  }
  if (others > 0) kept.add(MapEntry('Autres', others));
  return kept;
}

class _CategoryChart extends StatefulWidget {
  const _CategoryChart(this.data);
  final Map<String, double> data;

  @override
  State<_CategoryChart> createState() => _CategoryChartState();
}

class _CategoryChartState extends State<_CategoryChart> {
  int? _selected;

  static const _palette = [
    Color(0xFF2E7D32), Color(0xFF1565C0), Color(0xFFEF6C00), Color(0xFF6A1B9A), Color(0xFF78909C),
  ];

  void _select(int? i) => setState(() => _selected = (i == _selected) ? null : i);

  @override
  Widget build(BuildContext context) {
    final slices = groupCategories(widget.data);
    final total = slices.fold<double>(0, (s, e) => s + e.value);
    final selected = (_selected != null && _selected! < slices.length) ? slices[_selected!] : null;
    final details = selected?.key == 'Autres'
        ? (widget.data.entries.where((e) => !slices.any((s) => s.key == e.key)).toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        : const <MapEntry<String, double>>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox(
          width: 150,
          height: 150,
          child: PieChart(PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 30,
            pieTouchData: PieTouchData(
              touchCallback: (event, response) {
                if (event is FlTapUpEvent) _select(response?.touchedSection?.touchedSectionIndex);
              },
            ),
            sections: [
              for (var i = 0; i < slices.length; i++)
                PieChartSectionData(
                  value: slices[i].value,
                  color: _palette[i % _palette.length],
                  radius: i == _selected ? 46 : 38,
                  title: total == 0 ? '' : '${(slices[i].value / total * 100).round()} %',
                  titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                ),
            ],
          )),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < slices.length; i++)
              InkWell(
                onTap: () => _select(i),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(children: [
                    Container(width: 10, height: 10, color: _palette[i % _palette.length]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        slices[i].key,
                        style: TextStyle(fontSize: 12, fontWeight: i == _selected ? FontWeight.bold : null),
                      ),
                    ),
                    Text(formatDt(slices[i].value), style: const TextStyle(fontSize: 12)),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
      if (selected != null)
        Card(
          margin: const EdgeInsets.only(top: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${selected.key} : ${formatDt(selected.value)} (${(selected.value / total * 100).round()} % du mois)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final d in details) Text('• ${d.key} : ${formatDt(d.value)}'),
            ]),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Touchez une part pour le détail.', style: Theme.of(context).textTheme.bodySmall),
        ),
    ]);
  }
}

// ------------------------------------------------------------------ Badges

class _BadgesGrid extends StatelessWidget {
  const _BadgesGrid(this.badges);
  final List<Achievement> badges;

  static IconData _icon(String id) => switch (id) {
        'budget3' => Icons.emoji_events,
        'zero_oubli' => Icons.task_alt,
        'scanner' => Icons.receipt_long,
        'liste_bouclee' => Icons.checklist_rtl,
        _ => Icons.travel_explore,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final b in badges)
        Tooltip(
          message: b.description,
          triggerMode: TooltipTriggerMode.tap,
          child: Container(
            width: 104,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: b.unlocked ? Colors.amber.withValues(alpha: 0.18) : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: b.unlocked ? Colors.amber.shade700 : Colors.transparent),
            ),
            child: Column(children: [
              Icon(_icon(b.id), color: b.unlocked ? Colors.amber.shade800 : scheme.outline, size: 30),
              const SizedBox(height: 4),
              Text(b.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: b.progress, minHeight: 5),
              ),
              const SizedBox(height: 2),
              Text(b.progressText, style: Theme.of(context).textTheme.labelSmall),
            ]),
          ),
        ),
    ]);
  }
}

// ---------------------------------------------------------------- Dialogue

class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({required this.month, this.amount, required this.threshold});
  final DateTime month;
  final double? amount;
  final int threshold;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final _amount = TextEditingController(text: widget.amount == null ? '' : formatDt(widget.amount!, symbol: false));
  late double _threshold = widget.threshold.toDouble();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Budget de ${monthLabel(widget.month)}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Montant', suffixText: 'DT', errorText: _error),
          ),
          const SizedBox(height: 16),
          Text('Alerte (vibration) à ${_threshold.round()} % du budget'),
          Slider(
            value: _threshold,
            min: 50,
            max: 100,
            divisions: 10,
            label: '${_threshold.round()} %',
            onChanged: (v) => setState(() => _threshold = v),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final v = parseNumber(_amount.text);
              if (v == null || v <= 0) return setState(() => _error = 'Montant invalide');
              Navigator.pop(context, (v, _threshold.round()));
            },
            child: const Text('Enregistrer'),
          ),
        ],
      );
}
