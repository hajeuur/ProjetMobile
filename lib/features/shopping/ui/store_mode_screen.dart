import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../logic/budget_forecast.dart' show BudgetLevel;
import '../logic/store_mode.dart';
import '../models/dates.dart';
import '../models/live_cart.dart';
import '../models/shopping_list.dart';
import '../services/product_scan_service.dart';
import '../services/shopping_service.dart';
import '../viewmodels/live_cart_view_model.dart';
import '../viewmodels/store_mode_view_model.dart';
import 'barcode_scanner_screen.dart';
import 'live_cart_screen.dart';
import 'widgets.dart';

/// Lecteur de code-barres (remplaçable dans les tests).
typedef BarcodeScan = Future<String?> Function(BuildContext context, {required bool demoMode});

Future<String?> _cameraScan(BuildContext context, {required bool demoMode}) =>
    Navigator.push<String>(context, MaterialPageRoute(builder: (_) => BarcodeScannerScreen(demoMode: demoMode)));

/// Mode magasin d'une liste : gros boutons, articles groupés par rayon dans
/// l'ordre du magasin, filtre « restants », progression, panier en direct et
/// scan. Écran toujours allumé, retour haptique à chaque article coché,
/// contraste sombre à la demande, tout à portée de pouce en bas.
class StoreModeScreen extends StatelessWidget {
  const StoreModeScreen({super.key, required this.listId, this.scanner = _cameraScan});

  final int listId;
  final BarcodeScan scanner;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) =>
        StoreModeViewModel(context.read<ShoppingService>(), context.read<ProductScanService>(), listId)..load(),
    child: _StoreModeView(scanner: scanner),
  );
}

/// Thème sombre à fort contraste (rayons mal éclairés, écran au soleil
/// atténué) : fond noir, texte blanc, vert vif pour ce qui est pris.
ThemeData storeDarkTheme(ThemeData base) {
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.green,
    brightness: Brightness.dark,
  ).copyWith(surface: Colors.black, onSurface: Colors.white, primary: Colors.greenAccent.shade400);
  return base.copyWith(
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.black,
    cardColor: const Color(0xFF1B1B1B),
    appBarTheme: const AppBarTheme(backgroundColor: Colors.black, foregroundColor: Colors.white),
    textTheme: base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
  );
}

class _StoreModeView extends StatefulWidget {
  const _StoreModeView({required this.scanner});
  final BarcodeScan scanner;

  @override
  State<_StoreModeView> createState() => _StoreModeViewState();
}

class _StoreModeViewState extends State<_StoreModeView> {
  late final StoreModeViewModel _vm = context.read<StoreModeViewModel>();

  @override
  void initState() {
    super.initState();
    keepScreenOn(true);
  }

  @override
  void dispose() {
    keepScreenOn(false);
    _vm.finishTrip(); // l'ordre de visite des rayons est mémorisé
    super.dispose();
  }

  Future<void> _toggle(ShoppingItem item) async {
    final checking = !item.checked;
    final willFinish = checking && _vm.done == _vm.total - 1;
    if (_vm.haptics) {
      if (willFinish) {
        HapticFeedback.heavyImpact();
      } else if (checking) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.selectionClick();
      }
    }
    await _vm.toggle(item);
  }

  Future<void> _scan() async {
    final demo = (await _vm.service.settings()).demoProducts;
    if (!mounted) return;
    final code = await widget.scanner(context, demoMode: demo);
    if (code == null || !mounted) return;
    final r = await _vm.scanned(code);
    if (!mounted) return;
    if (_vm.liveCart && !r.inCart) {
      // Prix inconnu : saisi depuis l'étiquette.
      final item = await showDialog<LiveCartItem>(
        context: context,
        builder: (_) => CartPriceDialog(name: r.name, barcode: code),
      );
      if (item == null || !mounted) return;
      await _vm.addToCart(item);
      if (mounted) _afterCart(item.label);
      return;
    }
    if (_vm.haptics) HapticFeedback.mediumImpact();
    if (r.inCart) {
      _afterCart(r.name);
    } else {
      showSnack(context, r.checked ? '« ${r.name} » coché sur la liste' : '« ${r.name} » n\'est pas sur cette liste');
    }
  }

  Future<void> _manual() async {
    final item = await showDialog<LiveCartItem>(context: context, builder: (_) => const CartPriceDialog());
    if (item == null || !mounted) return;
    await _vm.addToCart(item);
    if (mounted) _afterCart(item.label);
  }

  void _afterCart(String name) {
    final cart = _vm.cart;
    if (cart.alert != null && _vm.haptics) HapticFeedback.heavyImpact();
    showSnack(context, '« $name » dans le panier · ${formatDt(cart.total)}');
  }

  Future<void> _openCart() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveCartScreen()));
    if (!mounted) return;
    await _vm.cart.load();
    await _vm.reloadItems();
  }

  Future<void> _reorder() async {
    final order = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReorderSheet(aisles: _vm.listAisles),
    );
    if (order != null) await _vm.reorder(order);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StoreModeViewModel>();
    final base = Theme.of(context);
    return Theme(
      data: vm.dark ? storeDarkTheme(base) : base,
      child: Builder(builder: (context) => _scaffold(context, vm)),
    );
  }

  Widget _scaffold(BuildContext context, StoreModeViewModel vm) {
    final groups = vm.groups;
    return Scaffold(
      appBar: AppBar(
        title: Text(vm.list?.name ?? 'Mode magasin', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: vm.dark ? 'Affichage clair' : 'Affichage sombre contrasté',
            icon: Icon(vm.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: vm.toggleDark,
          ),
          PopupMenuButton<Object>(
            tooltip: 'Tri des rayons',
            icon: const Icon(Icons.sort),
            onSelected: (v) => v is StoreSort ? vm.setSort(v) : _reorder(),
            itemBuilder: (_) => [
              for (final s in StoreSort.values)
                CheckedPopupMenuItem<Object>(value: s, checked: vm.sort == s, child: Text(s.label)),
              const PopupMenuDivider(),
              const PopupMenuItem<Object>(
                value: 'reorder',
                child: ListTile(
                  leading: Icon(Icons.swap_vert),
                  title: Text('Réorganiser les rayons'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: vm.loading
          ? const Center(child: CircularProgressIndicator())
          : vm.error != null
          ? EmptyState(
              icon: Icons.error_outline,
              title: 'Mode magasin indisponible',
              message: vm.error,
              action: FilledButton(onPressed: vm.load, child: const Text('Réessayer')),
            )
          : Column(
              children: [
                _ProgressHeader(vm: vm),
                Expanded(
                  child: vm.total == 0
                      ? const EmptyState(
                          icon: Icons.add_shopping_cart,
                          title: 'Liste vide',
                          message: 'Ajoute des articles à la liste avant d\'aller en magasin.',
                        )
                      : groups.isEmpty
                      ? EmptyState(
                          icon: Icons.celebration_outlined,
                          title: 'Tout est dans le chariot !',
                          message: 'Il ne reste rien à prendre.',
                          action: OutlinedButton(
                            onPressed: vm.toggleRemaining,
                            child: const Text('Voir tous les articles'),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                          children: [
                            if (vm.finished && !vm.remainingOnly) const _DoneBanner(),
                            for (final g in groups) ...[
                              _AisleHeader(group: g, grouped: vm.sort != StoreSort.added),
                              for (final i in g.items) _BigItem(item: i, onTap: () => _toggle(i)),
                            ],
                          ],
                        ),
                ),
              ],
            ),
      // Tout ce qui sert souvent est en bas, sous le pouce.
      bottomNavigationBar: vm.loading || vm.error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (vm.liveCart)
                      ChangeNotifierProvider.value(
                        value: vm.cart,
                        child: _CartBar(onTap: _openCart),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: FilledButton.icon(
                            onPressed: _scan,
                            icon: const Icon(Icons.qr_code_scanner, size: 28),
                            label: const Text('Scanner', style: TextStyle(fontSize: 18)),
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                          ),
                        ),
                        if (vm.liveCart) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: OutlinedButton.icon(
                              onPressed: _manual,
                              icon: const Icon(Icons.keyboard),
                              label: const Text('Sans code'),
                              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// « 12/18 articles », barre de progression et filtre Tous / Restants.
class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.vm});
  final StoreModeViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = vm.finished
        ? (dark ? Colors.greenAccent.shade400 : Colors.green.shade700)
        : theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  vm.progressLabel,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Tous')),
                  ButtonSegment(value: true, label: Text('Restants')),
                ],
                selected: {vm.remainingOnly},
                showSelectedIcon: false,
                onSelectionChanged: (_) => vm.toggleRemaining(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: vm.total == 0 ? 0 : vm.done / vm.total),
              duration: const Duration(milliseconds: 300),
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 12,
                color: color,
                backgroundColor: color.withValues(alpha: 0.18),
                semanticsLabel: 'Progression : ${vm.progressLabel}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneBanner extends StatelessWidget {
  const _DoneBanner();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = dark ? Colors.greenAccent.shade400 : Colors.green.shade800;
    return Card(
      color: c.withValues(alpha: 0.14),
      child: ListTile(
        leading: Icon(Icons.celebration_outlined, color: c, size: 32),
        title: Text(
          'Tout est pris !',
          style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        subtitle: const Text('Direction la caisse.'),
      ),
    );
  }
}

class _AisleHeader extends StatelessWidget {
  const _AisleHeader({required this.group, required this.grouped});
  final AisleGroup group;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ok = dark ? Colors.greenAccent.shade400 : Colors.green.shade700;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 4),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            Expanded(
              child: Text(
                grouped ? group.aisle : allItemsTitle,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 0.3),
              ),
            ),
            if (group.complete) Icon(Icons.check_circle, color: ok, size: 20),
            const SizedBox(width: 4),
            Text('${group.done}/${group.items.length}', style: theme.textTheme.titleSmall),
          ],
        ),
      ),
    );
  }
}

/// Article en grand : toute la ligne est une cible tactile (72 px de haut).
class _BigItem extends StatelessWidget {
  const _BigItem({required this.item, required this.onTap});
  final ShoppingItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ok = dark ? Colors.greenAccent.shade400 : Colors.green.shade700;
    final qty = formatQuantity(item.quantity, item.unit);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Semantics(
        checked: item.checked,
        button: true,
        label: item.label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      item.checked ? Icons.check_circle : Icons.radio_button_unchecked,
                      key: ValueKey(item.checked),
                      size: 40,
                      color: item.checked ? ok : theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        decoration: item.checked ? TextDecoration.lineThrough : null,
                        color: item.checked ? theme.colorScheme.onSurface.withValues(alpha: 0.5) : null,
                      ),
                    ),
                  ),
                  if (qty.isNotEmpty)
                    Text(
                      qty,
                      style: TextStyle(
                        fontSize: 18,
                        color: theme.colorScheme.onSurface.withValues(alpha: item.checked ? 0.5 : 0.85),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Panier en direct : total et budget « si je passe en caisse ».
class _CartBar extends StatelessWidget {
  const _CartBar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<LiveCartViewModel>();
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final b = cart.budget;
    final color = switch (b?.level) {
      BudgetLevel.exceeded => dark ? Colors.red.shade300 : Colors.red.shade700,
      BudgetLevel.threshold => dark ? Colors.orange.shade300 : Colors.orange.shade800,
      _ => dark ? Colors.greenAccent.shade400 : Colors.green.shade700,
    };
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.shopping_cart_outlined, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Panier : ${formatDt(cart.total)}'
                      '${cart.count == 0 ? '' : ' · ${plural(cart.count, 'article')}'}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (b != null)
                      Text(
                        '${b.sentence}.',
                        style: TextStyle(color: color, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// « Réorganiser les rayons » : glisser pour mettre l'ordre du magasin.
class _ReorderSheet extends StatefulWidget {
  const _ReorderSheet({required this.aisles});
  final List<String> aisles;

  @override
  State<_ReorderSheet> createState() => _ReorderSheetState();
}

class _ReorderSheetState extends State<_ReorderSheet> {
  late final _aisles = [...widget.aisles];

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ordre des rayons dans ce magasin', style: Theme.of(context).textTheme.titleMedium),
          const Text('Glisse les rayons dans l\'ordre où tu les parcours. Cet ordre est mémorisé.'),
          const SizedBox(height: 8),
          Flexible(
            child: ReorderableListView(
              shrinkWrap: true,
              onReorderItem: (from, to) => setState(() => _aisles.insert(to, _aisles.removeAt(from))),
              children: [
                for (var i = 0; i < _aisles.length; i++)
                  ListTile(
                    key: ValueKey(_aisles[i]),
                    leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                    title: Text(_aisles[i]),
                    trailing: const Icon(Icons.drag_handle),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(onPressed: () => Navigator.pop(context, _aisles), child: const Text('Enregistrer')),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
