import 'package:flutter/material.dart';

import '../models/dates.dart';
import '../viewmodels/shopping_lists_view_model.dart';
import 'widgets.dart';

/// Confirmation de l'ajout vocal : les articles détectés, modifiables ou
/// supprimables ligne par ligne, puis « Ajouter à la liste ».
class VoiceConfirmScreen extends StatefulWidget {
  const VoiceConfirmScreen({super.key, required this.sentence, required this.drafts, required this.viewModel});

  final String sentence;
  final List<VoiceDraft> drafts;
  final ListDetailViewModel viewModel;

  @override
  State<VoiceConfirmScreen> createState() => _VoiceConfirmScreenState();
}

class _Row {
  _Row(this.draft)
      : label = TextEditingController(text: draft.label),
        qty = TextEditingController(text: draft.quantity == null ? '' : formatQuantity(draft.quantity, null));
  final VoiceDraft draft;
  final TextEditingController label;
  final TextEditingController qty;
  final key = UniqueKey();

  void dispose() {
    label.dispose();
    qty.dispose();
  }
}

class _VoiceConfirmScreenState extends State<VoiceConfirmScreen> {
  late final List<_Row> _rows = [for (final d in widget.drafts) _Row(d)];
  bool _saving = false;

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _labelChanged(_Row r, String v) async {
    r.draft.label = v.trim();
    final existing = await widget.viewModel.findExisting(v);
    if (mounted && r.draft.label == v.trim()) setState(() => r.draft.existing = existing);
  }

  void _qtyChanged(_Row r, String v) {
    setState(() => r.draft.quantity = v.trim().isEmpty ? null : parseNumber(v));
  }

  void _addRow() => setState(() => _rows.add(_Row(VoiceDraft(label: ''))));

  Future<void> _save() async {
    for (final r in _rows) {
      r.draft.label = r.label.text.trim();
    }
    final drafts = [for (final r in _rows) if (r.draft.label.isNotEmpty) r.draft];
    if (drafts.isEmpty) {
      showSnack(context, 'Aucun article à ajouter.');
      return;
    }
    setState(() => _saving = true);
    try {
      final n = await widget.viewModel.addVoiceItems(drafts);
      if (mounted) Navigator.pop(context, n);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, errorText(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = _rows.where((r) => r.label.text.trim().isNotEmpty).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Articles dictés')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.record_voice_over),
            title: Text('« ${widget.sentence} »'),
            subtitle: const Text('Vérifiez les articles détectés avant de les ajouter.'),
          ),
        ),
        if (_rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Aucun article reconnu dans la phrase. Ajoutez-en un ci-dessous.'),
          ),
        for (final r in _rows)
          Card(
            key: r.key,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.mic, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: r.label,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Article', isDense: true),
                      onChanged: (v) => _labelChanged(r, v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      controller: r.qty,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Qté', isDense: true),
                      onChanged: (v) => _qtyChanged(r, v),
                    ),
                  ),
                  if (r.draft.unit != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 6, top: 12),
                      child: Text(r.draft.unit!, style: theme.textTheme.bodySmall),
                    ),
                  IconButton(
                    tooltip: 'Retirer',
                    icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                    onPressed: () => setState(() {
                      _rows.remove(r);
                      r.dispose();
                    }),
                  ),
                ]),
                if (r.draft.existing != null) _ExistingNotice(draft: r.draft, onChanged: () => setState(() {})),
              ]),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add), label: const Text('Ajouter une ligne')),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _saving || count == 0 ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.playlist_add),
            label: Text('Ajouter à la liste ($count)'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ),
      ),
    );
  }
}

/// « Déjà dans la liste » : augmenter la quantité plutôt qu'un doublon.
class _ExistingNotice extends StatelessWidget {
  const _ExistingNotice({required this.draft, required this.onChanged});
  final VoiceDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final e = draft.existing!;
    final preview = draft.mergePreview;
    final color = Colors.orange.shade800;
    if (preview == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, right: 8),
        child: Text(
          'Déjà dans la liste (${e.quantityText.isEmpty ? e.label : '${e.label}, ${e.quantityText}'}) avec une autre '
          'unité : il sera ajouté à part.',
          style: TextStyle(color: color, fontSize: 12),
        ),
      );
    }
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(right: 4),
      value: draft.mergeIntoExisting,
      onChanged: (v) {
        draft.mergeIntoExisting = v;
        onChanged();
      },
      title: Text('Déjà dans la liste : « ${e.label} »', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      subtitle: Text(draft.mergeIntoExisting ? 'Augmenter la quantité : $preview' : 'Sera ajouté comme un nouvel article'),
    );
  }
}
