import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/themealdb_api.dart';
import '../services/recipe_service.dart';
import 'recipe_detail_screen.dart';
import 'widgets.dart';

enum _SearchMode {
  name('Nom'),
  category('Catégorie'),
  ingredient('Ingrédient');

  const _SearchMode(this.label);
  final String label;
}

/// Recherche et import de recettes TheMealDB.
class RecipeImportScreen extends StatefulWidget {
  const RecipeImportScreen({super.key});

  @override
  State<RecipeImportScreen> createState() => _RecipeImportScreenState();
}

class _RecipeImportScreenState extends State<RecipeImportScreen> {
  final _query = TextEditingController();
  _SearchMode _mode = _SearchMode.name;
  List<String> _categories = [];
  String? _category;
  List<MealSummary> _results = [];
  Set<String> _imported = {};
  String? _importing;
  bool _loading = false;
  bool _searched = false;
  bool _changed = false;
  String? _error;

  RecipeService get _service => context.read<RecipeService>();

  @override
  void initState() {
    super.initState();
    _loadImported();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadImported() async {
    final ids = await _service.repository.importedExternalIds(_service.userId);
    if (mounted) setState(() => _imported = ids);
  }

  Future<void> _loadCategories() async {
    if (_categories.isNotEmpty) return;
    try {
      final c = await _service.api.categories();
      if (mounted) setState(() => _categories = c);
    } on RecipeApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (_mode != _SearchMode.category && q.isEmpty) return;
    if (_mode == _SearchMode.category && _category == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = _service.api;
      final r = switch (_mode) {
        _SearchMode.name => await api.searchByName(q),
        _SearchMode.category => await api.filterByCategory(_category!),
        _SearchMode.ingredient => await api.filterByIngredient(q),
      };
      if (mounted) setState(() => _results = r);
    } on RecipeApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _searched = true;
        });
      }
    }
  }

  Future<void> _import(MealSummary m, {bool open = false}) async {
    setState(() => _importing = m.id);
    try {
      final id = await _service.importFromApi(m.id);
      _changed = true;
      if (!mounted) return;
      setState(() => _imported = {..._imported, m.id});
      if (open) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: id)));
      } else {
        showSnack(context, '« ${m.name} » importée.');
      }
    } on RecipeApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, 'Import impossible : $e');
    } finally {
      if (mounted) setState(() => _importing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Importer (TheMealDB)')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SegmentedButton<_SearchMode>(
              segments: [for (final m in _SearchMode.values) ButtonSegment(value: m, label: Text(m.label))],
              selected: {_mode},
              onSelectionChanged: (s) {
                setState(() => _mode = s.first);
                if (_mode == _SearchMode.category) _loadCategories();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _mode == _SearchMode.category
                ? DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Catégorie', border: OutlineInputBorder()),
                    items: [for (final c in _categories) DropdownMenuItem(value: c, child: Text(c))],
                    onChanged: (c) {
                      setState(() => _category = c);
                      _search();
                    },
                  )
                : TextField(
                    controller: _query,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: _mode == _SearchMode.name ? 'Nom de la recette' : 'Ingrédient principal',
                      hintText: _mode == _SearchMode.name ? 'ex. chicken, couscous, soup' : 'en anglais : chicken, rice, egg…',
                      suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _search),
                    ),
                  ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Icon(Icons.cloud_off, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!)),
              ]),
            ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(_searched && _error == null
                        ? 'Aucun résultat.'
                        : 'Les recettes TheMealDB sont en anglais.\nLes calories sont estimées à l\'import.',
                        textAlign: TextAlign.center),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      childAspectRatio: 0.78,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final m = _results[i];
                      final done = _imported.contains(m.id);
                      final busy = _importing == m.id;
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: busy ? null : () => _import(m, open: true),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Expanded(child: RecipeImage(m.thumbnail != null ? '${m.thumbnail}/preview' : null, radius: 0)),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                              child: Text(m.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: busy
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                                    )
                                  : done
                                      ? const Padding(
                                          padding: EdgeInsets.all(10),
                                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                                            Icon(Icons.check, color: Colors.green, size: 18),
                                            Text(' Importée'),
                                          ]),
                                        )
                                      : TextButton.icon(
                                          icon: const Icon(Icons.download, size: 18),
                                          label: const Text('Importer'),
                                          onPressed: () => _import(m),
                                        ),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
