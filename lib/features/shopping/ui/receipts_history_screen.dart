import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dates.dart';
import '../models/receipt.dart';
import '../viewmodels/receipts_view_model.dart';
import 'receipt_detail_screen.dart';
import 'receipt_scan_screen.dart';
import 'widgets.dart';

/// Écran « Historique des tickets » : tri par date ou montant, recherche par
/// magasin.
class ReceiptsHistoryScreen extends StatelessWidget {
  const ReceiptsHistoryScreen({super.key});

  Future<void> _scan(BuildContext context) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceiptScanScreen()));
    if (context.mounted) await context.read<ReceiptsViewModel>().load();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReceiptsViewModel>();
    final receipts = vm.visible;
    return Scaffold(
      appBar: AppBar(title: const Text('Tickets de caisse')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_receipts',
        onPressed: () => _scan(context),
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scanner'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Rechercher par magasin',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: vm.search,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(
              child: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Trier :'),
                for (final s in ReceiptSort.values)
                  ChoiceChip(
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    label: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(s.label),
                      if (vm.sort == s) Icon(vm.descending ? Icons.arrow_downward : Icons.arrow_upward, size: 14),
                    ]),
                    selected: vm.sort == s,
                    onSelected: (_) => vm.setSort(s),
                  ),
              ]),
            ),
            Text('${receipts.length} · ${formatDt(vm.visibleTotal)}', style: Theme.of(context).textTheme.labelMedium),
          ]),
        ),
        Expanded(
          child: vm.loading && vm.receipts.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : vm.error != null
                  ? EmptyState(icon: Icons.error_outline, title: vm.error!)
                  : receipts.isEmpty
                      ? EmptyState(
                          icon: Icons.receipt_long,
                          title: vm.query.isEmpty ? 'Aucun ticket' : 'Aucun ticket pour ce magasin',
                          message: vm.query.isEmpty ? 'Scannez votre premier ticket de caisse.' : null,
                        )
                      : RefreshIndicator(
                          onRefresh: vm.load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
                            children: vm.sort == ReceiptSort.date
                                // Par date : regroupés par mois avec le total du mois.
                                ? [
                                    for (final g in vm.byMonth) ...[
                                      _MonthHeader(month: g.month, total: g.total, count: g.receipts.length),
                                      for (final r in g.receipts) _tile(context, vm, r),
                                    ],
                                  ]
                                : [for (final r in receipts) _tile(context, vm, r)],
                          ),
                        ),
        ),
      ]),
    );
  }
}

Widget _tile(BuildContext context, ReceiptsViewModel vm, Receipt r) => Dismissible(
      key: ValueKey(r.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade400,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => confirm(
        context,
        'Supprimer le ticket ?',
        'Ticket ${r.storeName ?? ''} du ${formatDate(r.date)} (${formatDt(r.total)}).',
      ),
      onDismissed: (_) => vm.delete(r),
      child: Card(
        child: ListTile(
          leading: StoreAvatar(name: r.storeName, type: vm.storeOf(r)?.type),
          title: Text(r.storeName ?? 'Magasin inconnu'),
          subtitle: Text('${formatDate(r.date)} · ${plural(r.lineCount, 'article')}'),
          trailing: Text(formatDt(r.total), style: Theme.of(context).textTheme.titleMedium),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptDetailScreen(receiptId: r.id!)));
            await vm.load();
          },
        ),
      ),
    );

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month, required this.total, required this.count});
  final DateTime month;
  final double total;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
        child: Row(children: [
          Expanded(
            child: Text(
              '${monthTitle(month)} : ${formatDt(total)}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          Text(plural(count, 'ticket'), style: Theme.of(context).textTheme.labelMedium),
        ]),
      );
}
