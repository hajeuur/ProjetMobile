import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dates.dart';
import '../models/shopping_list.dart';
import '../viewmodels/shopping_lists_view_model.dart';
import 'list_detail_screen.dart';
import 'shopping_settings_screen.dart';
import 'habitual_basket_screen.dart';
import 'widgets.dart';

/// Écran « Listes de courses ».
class ShoppingListsScreen extends StatefulWidget {
  const ShoppingListsScreen({super.key});

  @override
  State<ShoppingListsScreen> createState() => _ShoppingListsScreenState();
}

class _ShoppingListsScreenState extends State<ShoppingListsScreen> {
  bool _showDone = false;

  Future<void> _create() async {
    final vm = context.read<ShoppingListsViewModel>();
    final name = await promptText(context, title: 'Nouvelle liste', initial: 'Liste du ${formatDate(vm.service.now)}');
    if (name == null || !mounted) return;
    try {
      final id = await vm.create(name);
      if (mounted) await _open(id);
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  Future<void> _open(int id) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ListDetailScreen(listId: id)));
    if (mounted) await context.read<ShoppingListsViewModel>().load();
  }

  Future<void> _importShortages() async {
    final vm = context.read<ShoppingListsViewModel>();
    try {
      final n = await vm.importShortages();
      if (mounted) {
        showSnack(context, n == 0 ? 'Aucune nouvelle rupture prévue.' : '${plural(n, 'rupture prévue ajoutée', 'ruptures prévues ajoutées')} à la liste en cours.');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Gestion Stock indisponible : $e');
    }
  }

  Future<void> _menu(ShoppingList l, String action) async {
    final vm = context.read<ShoppingListsViewModel>();
    try {
      switch (action) {
        case 'rename':
          final name = await promptText(context, title: 'Renommer la liste', initial: l.name);
          if (name != null) await vm.rename(l, name);
        case 'archive':
          await vm.archive(l);
          if (mounted) showSnack(context, '« ${l.name} » archivée.');
        case 'reopen':
          await vm.reopen(l);
        case 'delete':
          if (await confirm(context, 'Supprimer la liste ?', '« ${l.name} » et ses ${l.itemCount} articles seront supprimés.')) {
            await vm.delete(l);
          }
      }
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ShoppingListsViewModel>();
    final lists = _showDone ? vm.done : vm.active;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Listes de courses'),
        actions: [
          IconButton(
            tooltip: 'Ajouter les ruptures prévues',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: _importShortages,
          ),
          IconButton(
            tooltip: 'Réglages',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShoppingSettingsScreen())),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text('En cours (${vm.active.length})')),
                ButtonSegment(value: true, label: Text('Terminées (${vm.done.length})')),
              ],
              selected: {_showDone},
              onSelectionChanged: (s) => setState(() => _showDone = s.first),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_lists',
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle liste'),
      ),
      body: vm.loading && lists.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : vm.error != null
              ? EmptyState(icon: Icons.error_outline, title: vm.error!)
              : lists.isEmpty
                  ? EmptyState(
                      icon: Icons.checklist,
                      title: _showDone ? 'Aucune liste terminée' : 'Aucune liste en cours',
                      message: _showDone
                          ? null
                          : 'Créez une liste, ou laissez les recettes et les ruptures de stock la remplir.',
                    )
                  : RefreshIndicator(
                      onRefresh: vm.load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                        // En tête des listes en cours : le panier type par magasin.
                        itemCount: lists.length + (_showDone ? 0 : 1),
                        itemBuilder: (_, index) {
                          if (!_showDone && index == 0) return const HabitualBasketCard(compact: true);
                          final i = _showDone ? index : index - 1;
                          return _ListCard(
                            list: lists[i],
                            storeName: vm.stores[lists[i].storeId]?.name,
                            onTap: () => _open(lists[i].id!),
                            onMenu: (a) => _menu(lists[i], a),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.list, required this.storeName, required this.onTap, required this.onMenu});
  final ShoppingList list;
  final String? storeName;
  final VoidCallback onTap;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    final done = list.status == ListStatus.done;
    final left = list.itemCount - list.checkedCount;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(list.name, style: Theme.of(context).textTheme.titleMedium)),
              PopupMenuButton<String>(
                onSelected: onMenu,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'rename', child: Text('Renommer')),
                  if (!done) const PopupMenuItem(value: 'archive', child: Text('Archiver (terminée)')),
                  if (done) const PopupMenuItem(value: 'reopen', child: Text('Remettre en cours')),
                  const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                ],
              ),
            ]),
            Text(
              [
                'Créée le ${formatDate(list.createdAt)}',
                ?storeName,
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: list.progress, minHeight: 6),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  list.itemCount == 0
                      ? 'vide'
                      : left == 0
                          ? 'tout est pris'
                          : '$left / ${list.itemCount} à prendre',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
