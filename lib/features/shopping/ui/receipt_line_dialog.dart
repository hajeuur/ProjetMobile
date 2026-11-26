import 'package:flutter/material.dart';

import '../logic/categories.dart';
import '../models/dates.dart';
import '../models/receipt.dart';
import 'widgets.dart';

/// Ajout ou correction d'une ligne de ticket mal lue.
Future<ReceiptLine?> editReceiptLine(BuildContext context, {ReceiptLine? line}) =>
    showDialog<ReceiptLine>(context: context, builder: (_) => _LineDialog(line: line));

class _LineDialog extends StatefulWidget {
  const _LineDialog({this.line});
  final ReceiptLine? line;

  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  late final _label = TextEditingController(text: widget.line?.label ?? '');
  late final _qty = TextEditingController(text: formatQuantity(widget.line?.quantity ?? 1, null));
  late final _price = TextEditingController(text: widget.line == null ? '' : formatDt(widget.line!.price, symbol: false));
  late final _barcode = TextEditingController(text: widget.line?.barcode ?? '');
  late String? _category = widget.line?.category;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _qty.dispose();
    _price.dispose();
    _barcode.dispose();
    super.dispose();
  }

  void _save() {
    final label = _label.text.trim();
    final qty = parseNumber(_qty.text);
    final price = parseNumber(_price.text);
    final code = _barcode.text.trim();
    if (label.isEmpty) return setState(() => _error = 'Le libellé est obligatoire.');
    if (qty == null || qty <= 0) return setState(() => _error = 'Quantité invalide.');
    if (price == null) return setState(() => _error = 'Prix invalide.');
    if (code.isNotEmpty && !RegExp(r'^\d{8,14}$').hasMatch(code)) {
      return setState(() => _error = 'Le code-barres doit contenir 8 à 14 chiffres.');
    }
    final base = widget.line;
    Navigator.pop(
      context,
      ReceiptLine(
        id: base?.id,
        receiptId: base?.receiptId,
        label: label,
        quantity: qty,
        price: price,
        // Libellé changé : le rapprochement produit est refait.
        productId: base?.label == label ? base?.productId : null,
        barcode: code.isEmpty ? null : code,
        category: _category ?? guessCategory(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.line == null ? 'Ajouter une ligne' : 'Corriger la ligne'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _label,
              autofocus: widget.line == null,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Libellé'),
            ),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Quantité'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Prix de la ligne', suffixText: 'DT'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: kCategories.contains(_category) ? _category : null,
              decoration: const InputDecoration(labelText: 'Catégorie'),
              hint: const Text('Automatique'),
              items: [for (final c in kCategories) DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _category = v),
            ),
            TextField(
              controller: _barcode,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Code-barres (facultatif)', helperText: 'Pour comparer sur Open Prices'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: _save, child: const Text('Valider')),
        ],
      );
}
