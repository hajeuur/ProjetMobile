import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/open_prices_api.dart';
import '../models/dates.dart';
import '../models/receipt.dart';
import '../services/shopping_service.dart';
import 'receipt_line_dialog.dart';
import 'reconciliation_screen.dart';
import 'widgets.dart';

/// Détail d'un ticket : correction des lignes, comparaison Open Prices,
/// rapprochement avec une liste, suppression.
class ReceiptDetailScreen extends StatefulWidget {
  const ReceiptDetailScreen({super.key, required this.receiptId});
  final int receiptId;

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  Receipt? _receipt;
  String? _listName;
  bool _loading = true;

  ShoppingService get _service => context.read<ShoppingService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _service.receipt(widget.receiptId);
    String? listName;
    if (r?.listId != null) listName = (await _service.list(r!.listId!))?.name;
    if (!mounted) return;
    setState(() {
      _receipt = r;
      _listName = listName;
      _loading = false;
    });
  }

  Future<void> _run(Future<void> Function() action, [String? done]) async {
    try {
      await action();
      if (done != null && mounted) showSnack(context, done);
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
    await _load();
  }

  Future<void> _lineMenu(ReceiptLine line) async {
    final r = _receipt!;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(line.label), subtitle: Text(formatDt(line.price))),
          ListTile(leading: const Icon(Icons.edit), title: const Text('Corriger la ligne'), onTap: () => Navigator.pop(c, 'edit')),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('Comparer avec Open Prices'),
            subtitle: const Text('Prix signalés par d\'autres utilisateurs'),
            onTap: () => Navigator.pop(c, 'compare'),
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Partager ce prix sur Open Prices'),
            onTap: () => Navigator.pop(c, 'share'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Supprimer la ligne'),
            onTap: () => Navigator.pop(c, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'edit':
        final l = await editReceiptLine(context, line: line);
        if (l != null) await _run(() => _service.saveLine(r, l), 'Ligne corrigée.');
      case 'compare':
        await showCommunityPrices(context, line);
      case 'share':
        if (await confirm(context, 'Partager ce prix ?',
            '${line.label} : ${formatDt(line.unitPrice)} chez ${r.storeName ?? 'ce magasin'}, le ${formatDate(r.date)}. '
                'Le prix sera public sur Open Prices.',
            ok: 'Partager')) {
          await _run(() => _service.sharePrice(r, line), 'Prix partagé, merci !');
        }
      case 'delete':
        await _run(() => _service.removeLine(r, line));
    }
  }

  Future<void> _reconcile() async {
    final lists = await _service.lists();
    if (!mounted) return;
    final id = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Rapprocher avec quelle liste ?')),
          for (final l in lists)
            ListTile(
              leading: const Icon(Icons.checklist),
              title: Text(l.name),
              subtitle: Text('${l.itemCount == l.checkedCount ? 'Tout est pris' : '${plural(l.itemCount - l.checkedCount, 'article')} à prendre'} · ${l.status.label}'),
              onTap: () => Navigator.pop(c, l.id),
            ),
        ]),
      ),
    );
    if (id == null) return;
    try {
      final res = await _service.reconcile(_receipt!.id!, id);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ReconciliationScreen(report: ReceiptReport(receiptId: _receipt!.id!, reconciliation: res)),
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
    await _load();
  }

  Future<void> _editTotal() async {
    final v = await promptText(context, title: 'Total du ticket', label: 'Total (DT)', initial: formatDt(_receipt!.total, symbol: false));
    final t = v == null ? null : parseNumber(v);
    if (t != null) await _run(() => _service.setReceiptTotal(_receipt!, t));
  }

  @override
  Widget build(BuildContext context) {
    final r = _receipt;
    return Scaffold(
      appBar: AppBar(
        title: Text(r?.storeName ?? 'Ticket'),
        actions: [
          if (r != null)
            IconButton(
              tooltip: 'Supprimer le ticket',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, 'Supprimer le ticket ?', 'Ses ${r.lines.length} lignes seront supprimées.')) {
                  await _service.deleteReceipt(r.id!);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      floatingActionButton: r == null
          ? null
          : FloatingActionButton.small(
              heroTag: 'fab_receipt_line',
              tooltip: 'Ajouter une ligne',
              onPressed: () async {
                final l = await editReceiptLine(context);
                if (l != null) await _run(() => _service.saveLine(r, l));
              },
              child: const Icon(Icons.add),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : r == null
              ? const EmptyState(icon: Icons.receipt_long, title: 'Ticket introuvable')
              : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 80), children: [
                  if (r.photo != null)
                    ExpansionTile(
                      leading: const Icon(Icons.image_outlined),
                      title: const Text('Photo du ticket'),
                      children: [ReceiptPhoto(r.photo, height: 360)],
                    ),
                  Card(
                    child: Column(children: [
                      ListTile(
                        leading: const Icon(Icons.event),
                        title: Text(formatDate(r.date)),
                        subtitle: Text(r.storeName ?? 'Magasin inconnu'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.payments_outlined),
                        title: Text('Total : ${formatDt(r.total)}'),
                        subtitle: (r.total - r.linesTotal).abs() >= 0.011
                            ? Text('Somme des lignes : ${formatDt(r.linesTotal)}',
                                style: TextStyle(color: Colors.orange.shade800))
                            : null,
                        trailing: const Icon(Icons.edit, size: 18),
                        onTap: _editTotal,
                      ),
                      ListTile(
                        leading: const Icon(Icons.checklist),
                        title: Text(_listName == null ? 'Aucune liste rapprochée' : 'Liste : $_listName'),
                        trailing: TextButton(onPressed: _reconcile, child: const Text('Rapprocher')),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Text('${plural(r.lines.length, 'ligne')} — touchez pour corriger ou comparer',
                      style: Theme.of(context).textTheme.labelLarge),
                  for (final l in r.lines)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      child: ListTile(
                        dense: true,
                        title: Text(l.label),
                        subtitle: Text([
                          if (l.quantity != 1) '${formatQuantity(l.quantity, null)} × ${formatDt(l.unitPrice)}',
                          l.category ?? '',
                          if (l.barcode != null) 'EAN ${l.barcode}',
                        ].where((s) => s.isNotEmpty).join(' · ')),
                        trailing: Text(formatDt(l.price), style: const TextStyle(fontWeight: FontWeight.bold)),
                        onTap: () => _lineMenu(l),
                      ),
                    ),
                ]),
    );
  }
}

/// Feuille « Comparer avec Open Prices ».
Future<void> showCommunityPrices(BuildContext context, ReceiptLine line) {
  final service = context.read<ShoppingService>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<PriceComparison>(
          future: service.compareWithCommunity(line),
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return ListTile(
                leading: const Icon(Icons.cloud_off),
                title: const Text('Comparaison impossible'),
                subtitle: Text('${snap.error}'),
              );
            }
            final cmp = snap.data!;
            final diff = cmp.difference;
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line.label, style: Theme.of(c).textTheme.titleMedium),
              Text('Vous avez payé ${formatDt(cmp.paid)} l\'unité.'),
              const SizedBox(height: 12),
              if (!cmp.hasData)
                Text(cmp.allPrices.isEmpty
                    ? 'Aucun prix signalé pour ce produit sur Open Prices.'
                    : 'Aucun prix en ${ShoppingService.currency} ; ${cmp.allPrices.length} prix dans d\'autres devises '
                        '(${cmp.otherCurrencies.join(', ')}).')
              else ...[
                Row(children: [
                  Expanded(child: StatTile(label: 'Prix moyen', value: formatDt(cmp.mean!))),
                  Expanded(child: StatTile(label: 'Le moins cher', value: formatDt(cmp.min!))),
                  Expanded(
                    child: StatTile(
                      label: 'Vous vs moyenne',
                      value: formatPct(diff ?? 0),
                      color: (diff ?? 0) > 0.05 ? Colors.red.shade600 : Colors.green.shade700,
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Text('${cmp.sameCurrency.length} prix signalés :', style: Theme.of(c).textTheme.labelLarge),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView(shrinkWrap: true, children: [
                    for (final p in cmp.sameCurrency.take(20))
                      ListTile(
                        dense: true,
                        title: Text(formatDt(p.price)),
                        subtitle: Text([
                          if (p.date != null) formatDate(p.date!),
                          ?p.locationName,
                        ].join(' · ')),
                      ),
                  ]),
                ),
              ],
              const SizedBox(height: 4),
              Text('Source : Open Prices (Open Food Facts)', style: Theme.of(c).textTheme.bodySmall),
            ]);
          },
        ),
      ),
    ),
  );
}
