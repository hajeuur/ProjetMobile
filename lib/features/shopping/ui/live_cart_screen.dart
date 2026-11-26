import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../logic/budget_forecast.dart' show BudgetLevel;
import '../models/dates.dart';
import '../models/live_cart.dart';
import '../services/product_scan_service.dart';
import '../services/shopping_devices.dart';
import '../services/shopping_service.dart';
import '../viewmodels/live_cart_view_model.dart';
import '../viewmodels/receipts_view_model.dart';
import 'barcode_scanner_screen.dart';
import 'budget_screen.dart' show BudgetGauge;
import 'receipt_scan_screen.dart';
import 'widgets.dart';

/// « Je fais mes courses » (mode magasin) : chaque code-barres scanné va dans
/// le panier virtuel ; la jauge du budget bouge en direct ; « Passer en
/// caisse » prépare le ticket à confirmer. Écran toujours allumé.
class LiveCartScreen extends StatelessWidget {
  const LiveCartScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => LiveCartViewModel(context.read<ShoppingService>(), context.read<ProductScanService>())..load(),
        child: const _LiveCartView(),
      );
}

class _LiveCartView extends StatefulWidget {
  const _LiveCartView();

  @override
  State<_LiveCartView> createState() => _LiveCartViewState();
}

class _LiveCartViewState extends State<_LiveCartView> {
  @override
  void initState() {
    super.initState();
    keepScreenOn(true); // écran toujours allumé en magasin
  }

  @override
  void dispose() {
    keepScreenOn(false);
    super.dispose();
  }

  LiveCartViewModel get _vm => context.read<LiveCartViewModel>();

  Future<void> _scan() async {
    final demo = (await context.read<ShoppingService>().settings()).demoProducts;
    if (!mounted) return;
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => BarcodeScannerScreen(demoMode: demo)),
    );
    if (code == null || !mounted) return;
    final r = await _vm.addBarcode(code);
    if (!mounted) return;
    if (r.added) {
      _afterAdd(r.name);
    } else {
      // Prix inconnu (ni historique ni Open Prices) : saisie.
      await _manual(name: r.name, barcode: code);
    }
  }

  Future<void> _manual({String? name, String? barcode}) async {
    final item = await showDialog<LiveCartItem>(
      context: context,
      builder: (_) => CartPriceDialog(name: name, barcode: barcode),
    );
    if (item == null || !mounted) return;
    await _vm.add(item);
    if (mounted) _afterAdd(item.label);
  }

  void _afterAdd(String name) {
    HapticFeedback.selectionClick();
    final vm = _vm;
    if (vm.alert != null) HapticFeedback.heavyImpact();
    showSnack(context, '« $name » ajouté · panier ${formatDt(vm.total)}');
  }

  Future<void> _remove(int index) async {
    final item = await _vm.remove(index);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars() // l'« Annuler » passe avant les messages « ajouté » en attente
      ..showSnackBar(SnackBar(
        content: Text('« ${item.label} » retiré du panier'),
        action: SnackBarAction(label: 'Annuler', onPressed: () => _vm.undoRemove(index, item)),
      ));
  }

  Future<void> _checkout() async {
    final service = context.read<ShoppingService>();
    final vm = _vm;
    final scanVm = ReceiptScanViewModel(service, context.read<ReceiptReader>());
    await scanVm.init();
    await scanVm.useDraft(vm.draft());
    if (!mounted) return;
    final report = await Navigator.push<ReceiptReport>(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(value: scanVm, child: const ReceiptValidationScreen()),
      ),
    );
    if (report == null || !mounted) return;
    await vm.clear();
    if (!mounted) return;
    await showReceiptOutcome(context, report);
    if (mounted) showSnack(context, 'Ticket enregistré : le panier est vidé.');
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LiveCartViewModel>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Je fais mes courses'),
        actions: [
          if (vm.items.isNotEmpty)
            IconButton(
              tooltip: 'Vider le panier',
              icon: const Icon(Icons.remove_shopping_cart_outlined),
              onPressed: () async {
                if (await confirm(context, 'Vider le panier ?', 'Les ${plural(vm.count, 'article')} seront retirés.', ok: 'Vider')) {
                  await vm.clear();
                }
              },
            ),
        ],
      ),
      body: vm.loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              _BudgetHeader(vm: vm),
              if (vm.alert != null) _SoftAlert(level: vm.alert!, onClose: vm.dismissAlert),
              Expanded(
                child: vm.items.isEmpty
                    ? const EmptyState(
                        icon: Icons.add_shopping_cart,
                        title: 'Panier vide',
                        message: 'Scanne chaque produit que tu mets dans ton chariot : le budget se met à jour '
                            'en direct et les articles de ta liste se cochent.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                        itemCount: vm.items.length,
                        itemBuilder: (_, i) => Dismissible(
                          key: ObjectKey(vm.items[i]),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red.shade400,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (_) => _remove(i),
                          child: _CartTile(item: vm.items[i], index: i),
                        ),
                      ),
              ),
            ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scanner'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _manual(),
                  icon: const Icon(Icons.keyboard),
                  label: const Text('Sans code'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: vm.items.isEmpty ? null : _checkout,
              icon: const Icon(Icons.point_of_sale),
              label: Text('Passer en caisse · ${formatDt(vm.total)}', style: theme.textTheme.titleMedium?.copyWith(
                color: vm.items.isEmpty ? null : theme.colorScheme.onPrimary,
              )),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Jauge du budget « si je passe en caisse maintenant ».
class _BudgetHeader extends StatelessWidget {
  const _BudgetHeader({required this.vm});
  final LiveCartViewModel vm;

  @override
  Widget build(BuildContext context) {
    final b = vm.budget!;
    final theme = Theme.of(context);
    final color = switch (b.level) {
      BudgetLevel.exceeded => Colors.red.shade700,
      BudgetLevel.threshold => Colors.orange.shade800,
      _ => Colors.green.shade700,
    };
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          if (b.budget != null)
            BudgetGauge(
              ratio: b.ratio,
              from: vm.previousRatio,
              threshold: b.budget!.alertThreshold / 100,
              size: 84,
              label: '',
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Panier : ${formatDt(vm.total)}', style: theme.textTheme.titleMedium),
              Text(
                vm.count == 0 ? 'Aucun article' : plural(vm.count, 'article'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Text('${b.sentence}.', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Alerte douce : le panier fait franchir le seuil ou le budget.
class _SoftAlert extends StatelessWidget {
  const _SoftAlert({required this.level, required this.onClose});
  final BudgetLevel level;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final exceeded = level == BudgetLevel.exceeded;
    final color = exceeded ? Colors.red.shade700 : Colors.orange.shade800;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Color.alphaBlend(color.withValues(alpha: 0.12), Theme.of(context).colorScheme.surface),
      child: ListTile(
        leading: Icon(exceeded ? Icons.error_outline : Icons.warning_amber, color: color),
        title: Text(
          exceeded ? 'Avec ce panier, le budget du mois est dépassé' : 'Avec ce panier, tu passes le seuil d\'alerte',
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
        subtitle: const Text('Rien n\'est payé : retire un article d\'un glissement si besoin.'),
        trailing: IconButton(icon: const Icon(Icons.close, semanticLabel: 'Fermer'), onPressed: onClose),
      ),
    );
  }
}

class _CartTile extends StatelessWidget {
  const _CartTile({required this.item, required this.index});
  final LiveCartItem item;
  final int index;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<LiveCartViewModel>();
    final step = item.perKilo ? 0.1 : 1.0;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '${formatDt(item.unitPrice)}${item.perKilo ? '/kg' : ''}'
                '${item.priceSource == null ? '' : ' · ${item.priceSource}'}'
                '${item.listItemId != null ? ' · coché sur la liste' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
          ),
          IconButton(
            tooltip: 'Moins',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => vm.setQuantity(index, double.parse((item.quantity - step).toStringAsFixed(2))),
          ),
          Text(formatQuantity(item.quantity, item.perKilo ? 'kg' : null)),
          IconButton(
            tooltip: 'Plus',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => vm.setQuantity(index, double.parse((item.quantity + step).toStringAsFixed(2))),
          ),
          SizedBox(
            width: 78,
            child: Text(formatDt(item.total), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    );
  }
}

/// Produit sans code-barres, ou prix introuvable : nom et prix saisis.
class CartPriceDialog extends StatefulWidget {
  const CartPriceDialog({super.key, this.name, this.barcode});
  final String? name;
  final String? barcode;

  @override
  State<CartPriceDialog> createState() => CartPriceDialogState();
}

class CartPriceDialogState extends State<CartPriceDialog> {
  late final _name = TextEditingController(text: widget.name ?? '');
  final _price = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.barcode == null ? 'Article sans code-barres' : 'Prix inconnu'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.barcode != null)
            const Text('Ni ton historique ni Open Prices ne connaissent ce prix : saisis celui de l\'étiquette.'),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Produit')),
          TextField(
            controller: _price,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Prix', suffixText: 'DT', errorText: _error),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final p = parseNumber(_price.text);
              if (_name.text.trim().isEmpty || p == null || p <= 0) {
                setState(() => _error = 'Nom et prix nécessaires.');
                return;
              }
              Navigator.pop(
                context,
                LiveCartItem(label: _name.text.trim(), unitPrice: p, barcode: widget.barcode, priceSource: 'saisi'),
              );
            },
            child: const Text('Ajouter'),
          ),
        ],
      );
}
