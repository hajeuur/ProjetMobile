import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/recipe_list_view_model.dart';
import 'recipe_detail_screen.dart';
import 'recipe_edit_screen.dart';
import 'recipe_import_screen.dart';
import 'widgets.dart';

class RecipeListScreen extends StatefulWidget {
  const RecipeListScreen({super.key});

  @override
  State<RecipeListScreen> createState() => _RecipeListScreenState();
}

class _RecipeListScreenState extends State<RecipeListScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(Widget screen) async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    // Toujours recharger : le stock a pu changer (repas cuisiné).
    if (changed ?? true) context.read<RecipeListViewModel>().load();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RecipeListViewModel>();
    final items = vm.items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recettes'),
        actions: [
          PopupMenuButton<RecipeSort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Trier',
            initialValue: vm.sort,
            onSelected: vm.setSort,
            itemBuilder: (_) => [
              for (final s in RecipeSort.values) PopupMenuItem(value: s, child: Text(s.label)),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: SearchBar(
                controller: _search,
                hintText: 'Titre ou ingrédient…',
                leading: const Icon(Icons.search),
                trailing: [
                  if (vm.query.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        vm.setQuery('');
                      },
                    ),
                ],
                onChanged: vm.setQuery,
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  FilterChip(
                    label: Text(vm.onlyCompatible
                        ? 'Compatibles foyer${vm.hiddenCount > 0 ? ' (${vm.hiddenCount} masquées)' : ''}'
                        : 'Toutes les recettes'),
                    selected: vm.onlyCompatible,
                    onSelected: vm.setOnlyCompatible,
                  ),
                  const SizedBox(width: 8),
                  for (final c in vm.categories) ...[
                    ChoiceChip(
                      label: Text(c),
                      selected: vm.category == c,
                      onSelected: (s) => vm.setCategory(s ? c : null),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ]),
        ),
      ),
      floatingActionButton: _AddButton(onCreate: () => _open(const RecipeEditScreen()), onImport: () => _open(const RecipeImportScreen())),
      body: RefreshIndicator(
        onRefresh: vm.load,
        child: vm.loading && items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : vm.error != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(vm.error!))])
                : items.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 80),
                        Icon(Icons.menu_book, size: 64),
                        SizedBox(height: 12),
                        Center(child: Text('Aucune recette. Créez-en une ou importez-la.')),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final it = items[i];
                          final r = it.recipe;
                          return ListTile(
                            leading: RecipeImage(r.photo, size: 56),
                            title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(recipeSubtitle(r)),
                              if (!it.verdict.allowed)
                                Text(it.verdict.reasons.join(' · '),
                                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
                            ]),
                            trailing: GaspiBadge(it.gaspi.score, expiring: it.gaspi.expiringSoon),
                            onTap: () => _open(RecipeDetailScreen(recipeId: r.id!)),
                          );
                        },
                      ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onCreate, required this.onImport});
  final VoidCallback onCreate;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
        heroTag: 'fab-recettes',
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
        onPressed: () => showModalBottomSheet(
          context: context,
          builder: (c) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('Créer une recette personnelle'),
                onTap: () {
                  Navigator.pop(c);
                  onCreate();
                },
              ),
              ListTile(
                leading: const Icon(Icons.cloud_download),
                title: const Text('Importer depuis TheMealDB'),
                onTap: () {
                  Navigator.pop(c);
                  onImport();
                },
              ),
            ]),
          ),
        ),
      );
}
