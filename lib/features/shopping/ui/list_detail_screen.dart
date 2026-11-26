import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../logic/categories.dart';
import '../logic/item_sorting.dart';
import '../logic/undo_history.dart';
import '../models/dates.dart';
import '../models/shopping_list.dart';
import '../services/shopping_devices.dart';
import '../services/shopping_service.dart';
import '../shopping_module.dart';
import '../viewmodels/shopping_lists_view_model.dart';
import 'receipt_scan_screen.dart';
import 'store_comparison_screen.dart';
import 'store_mode_screen.dart';
import 'suggestions_card.dart';
import 'voice_confirm_screen.dart';
import 'voice_input_sheet.dart';
import 'widgets.dart';

/// Écran « Détail d'une liste ».
class ListDetailScreen extends StatelessWidget {
  const ListDetailScreen({super.key, required this.listId});
  final int listId;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => ListDetailViewModel(context.read<ShoppingService>(), listId)..load(),
    child: const _ListDetailView(),
  );
}

class _ListDetailView extends StatefulWidget {
  const _ListDetailView();

  @override
  State<_ListDetailView> createState() => _ListDetailViewState();
}

class _ListDetailViewState extends State<_ListDetailView> with RouteAware, WidgetsBindingObserver {
  final _label = TextEditingController();
  final _qty = TextEditingController();
  final _focus = FocusNode();
  bool _searching = false;

  // ------------------------------------------- Secouer pour annuler

  StreamSubscription<void>? _shakes;
  bool _shakeEnabled = false;
  bool _voiceEnabled = false;
  bool _storeMode = false;
  bool _covered = false; // un autre écran est par-dessus
  bool _foreground = true; // application au premier plan
  ModalRoute<void>? _route;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<ShoppingService>().settings().then((s) {
      if (!mounted) return;
      _shakeEnabled = s.shakeToUndo;
      setState(() {
        _voiceEnabled = s.voiceInput;
        _storeMode = s.storeMode;
      });
      _updateShakeListening();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _route) {
      if (_route != null) ShoppingModule.routeObserver.unsubscribe(this);
      _route = route;
      ShoppingModule.routeObserver.subscribe(this, route);
    }
  }

  // L'écran n'écoute l'accéléromètre que lorsqu'il est visible.
  @override
  void didPushNext() {
    _covered = true;
    _updateShakeListening();
  }

  @override
  void didPopNext() {
    _covered = false;
    // Les réglages ont pu changer (écran Réglages ouvert par-dessus).
    context.read<ShoppingService>().settings().then((s) {
      if (!mounted) return;
      _shakeEnabled = s.shakeToUndo;
      setState(() {
        _voiceEnabled = s.voiceInput;
        _storeMode = s.storeMode;
      });
      _updateShakeListening();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updateShakeListening();
  }

  void _updateShakeListening() {
    final listen = _shakeEnabled && !_covered && _foreground;
    if (listen && _shakes == null) {
      _shakes = context.read<ShakeSource>().shakes().listen((_) => _undo());
    } else if (!listen && _shakes != null) {
      _shakes!.cancel();
      _shakes = null;
    }
  }

  /// Annule la dernière action (secousse ou menu), avec « Rétablir ».
  bool _undoing = false;

  Future<void> _undo() async {
    if (_undoing) return; // une secousse pendant une annulation en cours
    _undoing = true;
    final vm = context.read<ListDetailViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    final ItemAction? a;
    try {
      a = await vm.undo();
    } catch (e) {
      if (mounted) showSnack(context, 'Annulation impossible : ${errorText(e)}');
      return;
    } finally {
      _undoing = false;
    }
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    if (a == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Rien à annuler')));
      return;
    }
    await HapticFeedback.lightImpact();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Dernière action annulée : ${a.undoDescription}'),
        action: SnackBarAction(label: 'Rétablir', onPressed: _redo),
      ),
    );
  }

  Future<void> _redo() async {
    final vm = context.read<ListDetailViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    final a = await vm.redo();
    if (a == null || !mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Action rétablie : ${a.redoDescription}')));
  }

  @override
  void dispose() {
    _shakes?.cancel();
    ShoppingModule.routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _label.dispose();
    _qty.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final vm = context.read<ListDetailViewModel>();
    final label = _label.text.trim();
    if (label.isEmpty) return;
    // « 2 kg » → quantité 2, unité kg.
    final m = RegExp(r'^\s*([\d.,]+)\s*(.*)$').firstMatch(_qty.text);
    final qty = m == null ? null : parseNumber(m.group(1)!);
    final unit = m?.group(2)!.trim();
    try {
      await vm.add(label, quantity: qty, unit: (unit?.isEmpty ?? true) ? null : unit);
      _label.clear();
      _qty.clear();
      _focus.requestFocus();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  Future<void> _edit(ShoppingItem item) async {
    final vm = context.read<ListDetailViewModel>();
    final updated = await showDialog<ShoppingItem>(
      context: context,
      builder: (_) => _ItemDialog(item: item),
    );
    if (updated == null || !mounted) return;
    try {
      await vm.update(updated);
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  /// Supprime l'article, avec « Annuler » pendant quelques secondes.
  Future<void> _delete(ShoppingItem item) async {
    final vm = context.read<ListDetailViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    await vm.remove(item);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('« ${item.label} » supprimé.'),
          action: SnackBarAction(label: 'Annuler', onPressed: _undo),
        ),
      );
  }

  /// Ajout vocal : écoute, découpage de la phrase, confirmation, ajout.
  Future<void> _voice() async {
    final vm = context.read<ListDetailViewModel>();
    final result = await showVoiceInputSheet(context);
    if (!mounted || result == null) return;
    if (result.manual) {
      _focus.requestFocus();
      return;
    }
    final sentence = result.text!.trim();
    final drafts = await vm.prepareVoice(sentence);
    if (!mounted) return;
    final n = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => VoiceConfirmScreen(sentence: sentence, drafts: drafts, viewModel: vm),
      ),
    );
    if (mounted && n != null && n > 0) {
      showSnack(context, '${plural(n, 'article')} ajouté${n > 1 ? 's' : ''} par la voix.');
    }
  }

  Future<void> _scan() async {
    final vm = context.read<ListDetailViewModel>();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptScanScreen(listId: vm.listId)));
    if (mounted) await vm.load();
  }

  Future<void> _pickStore() async {
    final vm = context.read<ListDetailViewModel>();
    final chosen = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Magasin visé'), subtitle: Text('Les articles seront triés selon ses rayons.')),
            ListTile(
              leading: const Icon(Icons.clear),
              title: const Text('Aucun magasin'),
              onTap: () => Navigator.pop(c, -1),
            ),
            for (final s in vm.stores)
              ListTile(
                leading: Icon(s.id == vm.list?.storeId ? Icons.radio_button_checked : Icons.radio_button_off),
                title: Text(s.name),
                subtitle: Text([if (s.type != null) s.type!, '${s.aisles.length} rayons'].join(' · ')),
                onTap: () => Navigator.pop(c, s.id),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await vm.setStore(chosen == -1 ? null : chosen);
  }

  Future<void> _menu(String action) async {
    final vm = context.read<ListDetailViewModel>();
    switch (action) {
      case 'rename':
        final name = await promptText(context, title: 'Renommer la liste', initial: vm.list?.name ?? '');
        if (name != null) {
          try {
            await vm.rename(name);
          } catch (e) {
            if (mounted) showSnack(context, errorText(e));
          }
        }
      case 'undo':
        await _undo();
      case 'clear':
        final n = await vm.removeChecked();
        if (mounted) showSnack(context, '${plural(n, 'article retiré', 'articles retirés')}.');
      case 'archive':
        await vm.archive();
        if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ListDetailViewModel>();
    final list = vm.list;
    final items = vm.visibleItems;
    // Suggestions pour cette liste ; recalculées quand ses articles changent.
    final suggestions = SuggestionsCard(
      listId: vm.listId,
      revision: Object.hashAll(vm.items.map((i) => i.label)),
      onAdded: vm.load,
    );
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Rechercher un article', border: InputBorder.none),
                onChanged: vm.search,
              )
            : Text(list?.name ?? 'Liste'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Fermer la recherche' : 'Rechercher',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) vm.search('');
            },
          ),
          if (_storeMode)
            IconButton(
              tooltip: 'Mode magasin',
              icon: const Icon(Icons.storefront),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => StoreModeScreen(listId: vm.listId)),
                );
                if (mounted) await vm.load();
              },
            ),
          IconButton(
            tooltip: 'Comparer les magasins',
            icon: const Icon(Icons.compare_arrows),
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => StoreComparisonScreen(listId: vm.listId))),
          ),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'undo',
                child: ListTile(
                  leading: Icon(Icons.undo),
                  title: Text('Annuler la dernière action'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(value: 'rename', child: Text('Renommer')),
              PopupMenuItem(value: 'clear', child: Text('Retirer les articles cochés')),
              PopupMenuItem(value: 'archive', child: Text('Archiver (terminée)')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_list_scan',
        onPressed: _scan,
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scanner le ticket'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: ActionChip(
                    avatar: const Icon(Icons.storefront, size: 18),
                    label: Text(vm.store?.name ?? 'Choisir un magasin', overflow: TextOverflow.ellipsis),
                    onPressed: _pickStore,
                  ),
                ),
                const SizedBox(width: 8),
                SegmentedButton<ItemSort>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ItemSort.added,
                      icon: Icon(Icons.schedule, size: 18),
                      tooltip: 'Ordre d\'ajout',
                    ),
                    ButtonSegment(
                      value: ItemSort.aisle,
                      icon: Icon(Icons.view_agenda_outlined, size: 18),
                      tooltip: 'Par rayon',
                    ),
                  ],
                  selected: {vm.sort},
                  onSelectionChanged: (s) => vm.setSort(s.first),
                ),
              ],
            ),
          ),
          if (vm.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: vm.checkedCount / vm.items.length, minHeight: 6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${vm.checkedCount}/${vm.items.length}'),
                ],
              ),
            ),
          Expanded(
            child: vm.loading && vm.items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                ? Column(
                    children: [
                      if (vm.query.isEmpty) suggestions,
                      Expanded(
                        child: EmptyState(
                          icon: Icons.add_shopping_cart,
                          title: vm.query.isEmpty ? 'Liste vide' : 'Aucun article trouvé',
                          message: vm.query.isEmpty ? 'Ajoutez un article ci-dessous.' : null,
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      if (vm.query.isEmpty)
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: suggestions),
                      ..._rows(context, vm, items),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _AddBar(
        label: _label,
        qty: _qty,
        focus: _focus,
        onAdd: _add,
        onVoice: _voiceEnabled ? _voice : null,
      ),
    );
  }

  List<Widget> _rows(BuildContext context, ListDetailViewModel vm, List<ShoppingItem> items) {
    final out = <Widget>[];
    String? section;
    for (final item in items) {
      final s = item.checked ? 'Dans le panier' : (vm.sort == ItemSort.aisle ? aisleOf(item) : null);
      if (s != null && s != section) {
        out.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              s,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        );
      }
      section = s ?? section;
      out.add(
        Dismissible(
          key: ValueKey(item.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red.shade400,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => _delete(item),
          child: CheckboxListTile(
            value: item.checked,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (_) => vm.toggle(item),
            title: Text(
              item.label,
              style: item.checked
                  ? TextStyle(decoration: TextDecoration.lineThrough, color: Theme.of(context).colorScheme.outline)
                  : null,
            ),
            subtitle: Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (item.quantity != null) Text(item.quantityText),
                if (vm.sort == ItemSort.added) Text(aisleOf(item), style: Theme.of(context).textTheme.bodySmall),
                OriginChip(item.origin),
              ],
            ),
            secondary: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Modifier',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _edit(item),
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                  onPressed: () => _delete(item),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return out;
  }
}

class _AddBar extends StatelessWidget {
  const _AddBar({required this.label, required this.qty, required this.focus, required this.onAdd, this.onVoice});
  final TextEditingController label;
  final TextEditingController qty;
  final FocusNode focus;
  final VoidCallback onAdd;

  /// Null quand l'ajout vocal est désactivé dans les réglages.
  final VoidCallback? onVoice;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 4,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: label,
                focusNode: focus,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Ajouter un article', isDense: true),
                onSubmitted: (_) => onAdd(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: qty,
                decoration: const InputDecoration(hintText: 'Qté', isDense: true),
                onSubmitted: (_) => onAdd(),
              ),
            ),
            if (onVoice != null)
              IconButton(onPressed: onVoice, icon: const Icon(Icons.mic_none), tooltip: 'Ajouter par la voix'),
            IconButton.filled(onPressed: onAdd, icon: const Icon(Icons.add), tooltip: 'Ajouter'),
          ],
        ),
      ),
    ),
  );
}

class _ItemDialog extends StatefulWidget {
  const _ItemDialog({required this.item});
  final ShoppingItem item;

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late final _label = TextEditingController(text: widget.item.label);
  late final _qty = TextEditingController(
    text: widget.item.quantity == null ? '' : widget.item.quantityText.split(' ').first,
  );
  late final _unit = TextEditingController(text: widget.item.unit ?? '');
  late String _aisle = aisleOf(widget.item);

  @override
  void dispose() {
    _label.dispose();
    _qty.dispose();
    _unit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Modifier l\'article'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _label,
            decoration: const InputDecoration(labelText: 'Libellé'),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Quantité'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _unit,
                  decoration: const InputDecoration(labelText: 'Unité'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: kCategories.contains(_aisle) ? _aisle : 'Autre',
            decoration: const InputDecoration(labelText: 'Rayon'),
            items: [
              for (final c in kCategories)
                DropdownMenuItem(
                  value: c,
                  child: Text(c, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _aisle = v ?? _aisle),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(originIcon(widget.item.origin), size: 16),
              const SizedBox(width: 6),
              Flexible(child: Text('Origine : ${widget.item.origin.label}')),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(
        onPressed: () {
          final q = parseNumber(_qty.text);
          Navigator.pop(
            context,
            widget.item.copyWith(
              label: _label.text.trim(),
              quantity: q,
              clearQuantity: q == null,
              unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
              aisle: _aisle,
            ),
          );
        },
        child: const Text('Enregistrer'),
      ),
    ],
  );
}
