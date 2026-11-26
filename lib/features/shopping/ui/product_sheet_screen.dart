import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/open_prices_api.dart';
import '../logic/pack_format.dart';
import '../logic/product_price.dart';
import '../models/dates.dart';
import '../services/product_scan_service.dart';
import '../services/shopping_devices.dart';
import '../services/shopping_service.dart';
import '../viewmodels/product_sheet_view_model.dart';
import 'barcode_scanner_screen.dart';
import 'widgets.dart';

/// Scanner puis ouvrir la fiche du produit lu.
Future<void> scanProduct(BuildContext context) async {
  final demo = (await context.read<ShoppingService>().settings()).demoProducts;
  if (!context.mounted) return;
  final code = await Navigator.push<String>(
    context,
    MaterialPageRoute(builder: (_) => BarcodeScannerScreen(demoMode: demo)),
  );
  if (code == null || !context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductSheetScreen(code: code)));
}

/// Fiche produit : Open Food Facts (nom, marque, photo, Nutri-Score,
/// allergènes), mon dernier prix, prix moyen de la communauté (Open Prices),
/// verdict, courbe, alternative moins chère et actions.
class ProductSheetScreen extends StatelessWidget {
  const ProductSheetScreen({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => ProductSheetViewModel(context.read<ProductScanService>(), code)..load(),
        child: const _SheetView(),
      );
}

class _SheetView extends StatefulWidget {
  const _SheetView();

  @override
  State<_SheetView> createState() => _SheetViewState();
}

class _SheetViewState extends State<_SheetView> {
  bool _toldResync = false;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProductSheetViewModel>();
    final s = vm.sheet;
    if (vm.resynced && !_toldResync) {
      _toldResync = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showSnack(context, 'Réseau revenu : données resynchronisées.');
      });
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Fiche produit')),
      body: RefreshIndicator(
        onRefresh: vm.load,
        child: s == null
            ? ListView(children: [
                const SizedBox(height: 120),
                if (vm.loading) const Center(child: CircularProgressIndicator()),
                if (vm.error != null) EmptyState(icon: Icons.error_outline, title: vm.error!),
              ])
            : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
                _StatusChips(sheet: s),
                if (s.networkError != null) _NetworkCard(sheet: s, onRetry: vm.load),
                _ProductHeader(sheet: s),
                _PriceCard(sheet: s),
                if (s.history.length >= 2) _HistoryChart(sheet: s),
                if (s.alternative != null) _AlternativeCard(alt: s.alternative!),
                const SizedBox(height: 8),
                _Actions(sheet: s, canContribute: vm.canContribute),
              ]),
      ),
    );
  }
}

// ------------------------------------------------------------ En-tête

class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.sheet});
  final ProductSheet sheet;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (sheet.offline)
        Chip(
          avatar: const Icon(Icons.cloud_off, size: 18),
          label: Text('Données hors ligne${sheet.fetchedAt == null ? '' : ' · ${formatDate(sheet.fetchedAt!)}'}'),
          backgroundColor: Colors.orange.withValues(alpha: 0.15),
        ),
      if (sheet.demo)
        const Chip(avatar: Icon(Icons.science_outlined, size: 18), label: Text('Mode démo · prix fictifs')),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, children: chips);
  }
}

class _NetworkCard extends StatelessWidget {
  const _NetworkCard({required this.sheet, required this.onRetry});
  final ProductSheet sheet;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: ListTile(
          leading: const Icon(Icons.wifi_off),
          title: const Text('Pas de réseau'),
          subtitle: Text('${sheet.networkError} Votre historique reste affiché ; nouvel essai automatique.'),
          trailing: TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ),
      );
}

class _ProductHeader extends StatelessWidget {
  const _ProductHeader({required this.sheet});
  final ProductSheet sheet;

  @override
  Widget build(BuildContext context) {
    final p = sheet.product;
    final theme = Theme.of(context);
    if (p == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.help_outline, size: 36),
          title: Text(sheet.productUnknown ? 'Produit inconnu' : 'Fiche produit indisponible'),
          subtitle: Text(sheet.productUnknown
              ? 'Le code ${sheet.code} n\'est pas dans Open Food Facts. Vous pouvez l\'y ajouter depuis '
                  'l\'application Open Food Facts.'
              : 'Code ${sheet.code}'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 84,
              height: 84,
              child: p.imageUrl == null
                  ? const ColoredBox(color: Colors.black12, child: Icon(Icons.image_not_supported_outlined))
                  : Image.network(
                      p.imageUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12, child: Icon(Icons.image_outlined)),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: theme.textTheme.titleLarge),
              Text([if (p.brands != null) p.brands!, if (p.quantity != null) p.quantity!].join(' · '),
                  style: theme.textTheme.bodyMedium),
              Text('Code ${p.code}', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                NutriScoreBadge(p.nutriscore),
                for (final a in p.allergens)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.warning_amber, size: 16),
                    label: Text(allergenLabel(a)),
                  ),
                if (p.allergens.isEmpty) Text('Aucun allergène déclaré', style: theme.textTheme.bodySmall),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Allergènes Open Food Facts (« en:milk ») en français.
String allergenLabel(String tag) {
  const fr = {
    'en:milk': 'Lait', 'en:nuts': 'Fruits à coque', 'en:peanuts': 'Arachides', 'en:soybeans': 'Soja',
    'en:gluten': 'Gluten', 'en:eggs': 'Œufs', 'en:fish': 'Poisson', 'en:crustaceans': 'Crustacés',
    'en:celery': 'Céleri', 'en:mustard': 'Moutarde', 'en:sesame-seeds': 'Sésame', 'en:lupin': 'Lupin',
    'en:molluscs': 'Mollusques', 'en:sulphur-dioxide-and-sulphites': 'Sulfites',
  };
  final known = fr[tag];
  if (known != null) return known;
  final t = tag.contains(':') ? tag.split(':').last : tag;
  return t.isEmpty ? tag : t[0].toUpperCase() + t.substring(1).replaceAll('-', ' ');
}

class NutriScoreBadge extends StatelessWidget {
  const NutriScoreBadge(this.grade, {super.key});
  final String? grade;

  static const _colors = {
    'a': Color(0xFF038141),
    'b': Color(0xFF85BB2F),
    'c': Color(0xFFFECB02),
    'd': Color(0xFFEE8100),
    'e': Color(0xFFE63E11),
  };

  @override
  Widget build(BuildContext context) {
    final g = grade;
    return Semantics(
      label: g == null ? 'Nutri-Score inconnu' : 'Nutri-Score ${g.toUpperCase()}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: _colors[g] ?? Colors.grey, borderRadius: BorderRadius.circular(8)),
        child: Text(
          g == null ? 'Nutri-Score ?' : 'Nutri-Score ${g.toUpperCase()}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Prix

class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.sheet});
  final ProductSheet sheet;

  @override
  Widget build(BuildContext context) {
    final s = sheet;
    final theme = Theme.of(context);
    final last = s.myLast;
    final mean = s.communityMean;
    final v = s.verdict;
    final vColor = switch (v.kind) {
      VerdictKind.expensive => Colors.red.shade700,
      VerdictKind.good => Colors.green.shade700,
      VerdictKind.unknown => theme.colorScheme.outline,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row(
            context,
            Icons.receipt_long,
            'Mon dernier prix payé',
            last == null ? '—' : formatDt(last.unitPrice),
            sub: last == null
                ? 'Jamais acheté (d\'après vos tickets)'
                : '${formatDate(last.date)}${last.store == null ? '' : ' · ${last.store}'}',
          ),
          const Divider(),
          if (!s.comparisonEnabled)
            _row(context, Icons.public_off, 'Prix de la communauté', 'désactivé',
                sub: 'Activez « Comparer avec Open Prices » dans les Réglages.')
          else
            _row(
              context,
              Icons.groups_outlined,
              'Prix moyen de la communauté',
              mean == null ? '—' : formatDt(mean),
              sub: mean != null
                  ? '${plural(s.community.length, 'prix comparé', 'prix comparés')} en DT (Open Prices)'
                  : s.otherCurrencyCount > 0
                      ? 'Aucun prix communautaire en DT (${plural(s.otherCurrencyCount, 'prix', 'prix')} dans d\'autres devises)'
                      : s.networkError != null
                          ? 'Indisponible hors ligne'
                          : 'Aucun prix communautaire pour ce produit',
            ),
          _PerKiloBadge(sheet: s),
          if (v.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: vColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: vColor),
              ),
              child: Row(children: [
                Icon(
                  switch (v.kind) {
                    VerdictKind.expensive => Icons.trending_up,
                    VerdictKind.good => Icons.thumb_up_alt_outlined,
                    VerdictKind.unknown => Icons.info_outline,
                  },
                  color: vColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(v.text, style: TextStyle(color: vColor, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value, {String? sub}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label),
              if (sub != null) Text(sub, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
      );
}

/// Badge « Prix au kilo » (ou au litre) : format Open Food Facts (« 400 g »)
/// et mon dernier prix, sinon la moyenne de la communauté.
class _PerKiloBadge extends StatelessWidget {
  const _PerKiloBadge({required this.sheet});
  final ProductSheet sheet;

  @override
  Widget build(BuildContext context) {
    final f = parsePackFormat(sheet.product?.quantity ?? '');
    final price = sheet.myLast?.unitPrice ?? sheet.communityMean;
    if (f == null || price == null) return const SizedBox.shrink();
    final kilo = f.measure == Measure.mass;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          avatar: Icon(kilo ? Icons.scale_outlined : Icons.water_drop_outlined, size: 18),
          label: Text('Prix ${kilo ? 'au kilo' : 'au litre'} : ${formatDt(f.pricePerBig(price))}/${f.measure.big}'
              '${sheet.myLast == null ? ' (moyenne)' : ''}'),
        ),
      ),
    );
  }
}

class _HistoryChart extends StatelessWidget {
  const _HistoryChart({required this.sheet});
  final ProductSheet sheet;

  @override
  Widget build(BuildContext context) {
    final h = sheet.history;
    final mean = sheet.communityMean;
    final first = h.first.date;
    final spots = [for (final p in h) FlSpot(p.date.difference(first).inDays.toDouble(), p.unitPrice)];
    final values = [...h.map((p) => p.unitPrice), ?mean];
    final minY = values.reduce((a, b) => a < b ? a : b) * 0.9;
    final maxY = values.reduce((a, b) => a > b ? a : b) * 1.1;
    final color = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text('Évolution de mon prix (${plural(h.length, 'achat')})',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          SizedBox(
            height: 170,
            child: LineChart(LineChartData(
              minY: minY,
              maxY: maxY,
              gridData: const FlGridData(drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (v, m) => Text(v.toStringAsFixed(1).replaceAll('.', ','), style: const TextStyle(fontSize: 10)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: spots.last.x == 0 ? 1 : spots.last.x,
                    getTitlesWidget: (v, m) {
                      final d = first.add(Duration(days: v.round()));
                      return Text('${d.day}/${d.month}', style: const TextStyle(fontSize: 10));
                    },
                  ),
                ),
              ),
              extraLinesData: ExtraLinesData(horizontalLines: [
                if (mean != null)
                  HorizontalLine(
                    y: mean,
                    color: Colors.blueGrey,
                    strokeWidth: 1.5,
                    dashArray: [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
                      labelResolver: (_) => 'moyenne communauté',
                    ),
                  ),
              ]),
              lineBarsData: [
                LineChartBarData(spots: spots, color: color, barWidth: 3, dotData: const FlDotData(show: true)),
              ],
            )),
          ),
        ]),
      ),
    );
  }
}

class _AlternativeCard extends StatelessWidget {
  const _AlternativeCard({required this.alt});
  final CheaperAlternative alt;

  @override
  Widget build(BuildContext context) {
    final green = Colors.green.shade700;
    final community = alt.source == AlternativeSource.community;
    return Card(
      color: Color.alphaBlend(Colors.green.withValues(alpha: 0.10), Theme.of(context).colorScheme.surface),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.savings_outlined, color: green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                community ? 'Alternative moins chère (même catégorie)' : 'Moins cher dans un autre magasin',
                style: TextStyle(color: green, fontWeight: FontWeight.bold),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(alt.name, style: Theme.of(context).textTheme.titleMedium),
          Text(community
              ? '${formatDt(alt.price)} en moyenne (${plural(alt.priceCount, 'prix', 'prix')}) · ${(alt.saving * 100).round()} % d\'économie'
              : '${formatDt(alt.price)} chez ${alt.where} · ${(alt.saving * 100).round()} % moins cher que votre dernier achat'),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                final list = await context.read<ProductSheetViewModel>().addToList(
                      community ? alt.name : '${alt.name} (${alt.where})',
                    );
                if (context.mounted) showSnack(context, '« ${alt.name} » ajouté à « $list ».');
              },
              icon: const Icon(Icons.playlist_add),
              label: const Text('Ajouter à ma liste'),
            ),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------- Actions

class _Actions extends StatelessWidget {
  const _Actions({required this.sheet, required this.canContribute});
  final ProductSheet sheet;
  final bool canContribute;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<ProductSheetViewModel>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FilledButton.icon(
        onPressed: () async {
          final list = await vm.addToList(sheet.listLabel);
          if (context.mounted) showSnack(context, '« ${sheet.listLabel} » ajouté à « $list ».');
        },
        icon: const Icon(Icons.playlist_add),
        label: const Text('Ajouter à ma liste'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () async {
          final on = await vm.toggleWatch();
          if (context.mounted) {
            showSnack(context, on ? 'Produit surveillé : retrouvez-le dans l\'onglet Prix.' : 'Surveillance arrêtée.');
          }
        },
        icon: Icon(sheet.watched ? Icons.notifications_active : Icons.notifications_none),
        label: Text(sheet.watched ? 'Produit surveillé' : 'Surveiller ce produit'),
      ),
      if (canContribute) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _contribute(context),
          icon: const Icon(Icons.volunteer_activism_outlined),
          label: const Text('Contribuer mon prix'),
        ),
      ],
    ]);
  }

  Future<void> _contribute(BuildContext context) async {
    final shopping = context.read<ShoppingService>();
    if (await shopping.tokens.read() == null) {
      if (context.mounted) {
        showSnack(context, 'Connectez-vous à Open Food Facts : Réglages › Partager mes prix.');
      }
      return;
    }
    if (!context.mounted) return;
    final input = await showDialog<_Contribution>(
      context: context,
      builder: (_) => _ContributeDialog(initialPrice: sheet.myLast?.unitPrice, today: shopping.now),
    );
    if (input == null || !context.mounted) return;
    try {
      final n = await context.read<ProductScanService>().contribute(
            code: sheet.code,
            price: input.price,
            date: input.date,
            proofPhoto: input.photo,
            proofType: input.proofType,
          );
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            icon: const Icon(Icons.favorite, color: Colors.pink),
            title: const Text('Merci pour votre contribution !'),
            content: Text('Votre prix aide la communauté Open Prices.\n'
                'Vous avez partagé ${plural(n, 'prix', 'prix')} depuis PanierMalin.'),
            actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
          ),
        );
      }
    } on OpenPricesException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }
}

class _Contribution {
  const _Contribution(this.price, this.date, this.photo, this.proofType);
  final double price;
  final DateTime date;
  final String photo;
  final String proofType;
}

/// Prix, date et preuve (photo du ticket ou de l'étiquette, exigée par Open Prices).
class _ContributeDialog extends StatefulWidget {
  const _ContributeDialog({required this.initialPrice, required this.today});
  final double? initialPrice;
  final DateTime today;

  @override
  State<_ContributeDialog> createState() => _ContributeDialogState();
}

class _ContributeDialogState extends State<_ContributeDialog> {
  late final _price = TextEditingController(
    text: widget.initialPrice == null ? '' : formatDt(widget.initialPrice!, symbol: false),
  );
  String _type = 'PRICE_TAG';
  String? _photo;
  String? _error;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _pick(PhotoSource source) async {
    try {
      final p = await context.read<ReceiptReader>().capture(source);
      if (p != null) setState(() => _photo = p);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Contribuer mon prix'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Prix payé', suffixText: 'DT'),
            ),
            const SizedBox(height: 12),
            const Text('Preuve demandée par Open Prices :'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'PRICE_TAG', label: Text('Étiquette')),
                ButtonSegment(value: 'RECEIPT', label: Text('Ticket')),
              ],
              selected: {_type},
              onSelectionChanged: (v) => setState(() => _type = v.first),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(PhotoSource.camera),
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Photo'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(PhotoSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galerie'),
                ),
              ),
            ]),
            if (_photo != null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Row(children: [Icon(Icons.check, color: Colors.green), SizedBox(width: 6), Text('Photo jointe')]),
              ),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final p = parseNumber(_price.text);
              if (p == null || p <= 0) return setState(() => _error = 'Prix invalide.');
              if (_photo == null) return setState(() => _error = 'Ajoutez la photo de l\'étiquette ou du ticket.');
              Navigator.pop(context, _Contribution(p, widget.today, _photo!, _type));
            },
            child: const Text('Envoyer'),
          ),
        ],
      );
}
