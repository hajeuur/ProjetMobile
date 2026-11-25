import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/meal_plan.dart';
import '../viewmodels/recipe_stats_view_model.dart';

class RecipeStatsScreen extends StatelessWidget {
  const RecipeStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RecipeStatsViewModel>();
    final theme = Theme.of(context);
    final fmt = DateFormat('d MMM', 'fr_FR');
    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques recettes')),
      body: RefreshIndicator(
        onRefresh: vm.load,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          if (vm.loading) const LinearProgressIndicator(),
          if (vm.error != null) Text(vm.error!),
          Row(children: [
            _Tile(label: 'Recettes', value: '${vm.recipeCount}'),
            _Tile(label: 'Personnelles', value: '${vm.personalCount}'),
            _Tile(label: 'Importées', value: '${vm.importedCount}'),
          ]),
          const SizedBox(height: 16),
          Text('Recettes les plus cuisinées', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (vm.mostCooked.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Aucun repas cuisiné pour l\'instant.'))
          else
            SizedBox(height: 40.0 * vm.mostCooked.length + 20, child: _MostCookedChart(vm.mostCooked)),
          const SizedBox(height: 24),
          Row(children: [
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => vm.goToWeek(-1)),
            Expanded(
              child: Text(
                'Calories moyennes par repas\nsemaine du ${fmt.format(vm.weekStart)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => vm.goToWeek(1)),
          ]),
          Row(children: [
            _Tile(label: 'Moyenne / repas', value: '${vm.weekAveragePerMeal.round()} kcal'),
            _Tile(label: 'Repas cuisinés', value: '${vm.weekCooked}'),
          ]),
          const SizedBox(height: 8),
          SizedBox(height: 220, child: _WeekChart(vm.week)),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Par personne, sur les repas planifiés et cuisinés.', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          ),
        ]),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              Text(label, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            ]),
          ),
        ),
      );
}

class _MostCookedChart extends StatelessWidget {
  const _MostCookedChart(this.data);
  final List<(String, int)> data;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final maxCount = data.map((d) => d.$2).fold(0, (a, b) => a > b ? a : b);
    // Barres horizontales simples : plus lisibles avec des titres longs.
    return Column(children: [
      for (final (title, count) in data)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 130, child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Expanded(
              child: LayoutBuilder(
                builder: (_, c) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 22,
                    width: c.maxWidth * (maxCount == 0 ? 0 : count / maxCount),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
            ),
            SizedBox(width: 32, child: Text(' $count', textAlign: TextAlign.right)),
          ]),
        ),
    ]);
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart(this.days);
  final List<DayCalories> days;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxY = days.fold<double>(0, (m, d) => d.averagePerMeal > m ? d.averagePerMeal : m);
    final today = dateKey(DateTime.now());
    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 800 : maxY * 1.2,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, _) {
              final d = days[group.x];
              return BarTooltipItem(
                '${rod.toY.round()} kcal\n${d.meals} repas, ${d.cooked} cuisiné(s)',
                TextStyle(color: scheme.onInverseSurface),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= days.length) return const SizedBox.shrink();
                return SideTitleWidget(meta: meta, child: Text(DateFormat('E', 'fr_FR').format(days[i].date)));
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: days[i].averagePerMeal,
                width: 18,
                color: dateKey(days[i].date) == today ? scheme.tertiary : scheme.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ]),
        ],
      ),
    );
  }
}
