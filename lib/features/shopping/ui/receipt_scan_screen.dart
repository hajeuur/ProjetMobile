import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/budget_forecast.dart';
import '../models/dates.dart';
import '../models/receipt.dart';
import '../services/shopping_devices.dart';
import '../services/shopping_service.dart';
import '../viewmodels/live_scan_view_model.dart';
import '../viewmodels/receipts_view_model.dart';
import 'live_receipt_scan_screen.dart';
import 'reconciliation_screen.dart';
import 'receipt_line_dialog.dart';
import 'widgets.dart';

/// Écran « Scan du ticket » : photo (caméra ou galerie), lecture du texte,
/// puis écran de validation des lignes.
class ReceiptScanScreen extends StatelessWidget {
  const ReceiptScanScreen({super.key, this.listId});

  /// Liste à rapprocher avec le ticket (depuis le détail d'une liste).
  final int? listId;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => ReceiptScanViewModel(
          context.read<ShoppingService>(),
          context.read<ReceiptReader>(),
          listId: listId,
        )..init(),
        child: const _ScanView(),
      );
}

class _ScanView extends StatelessWidget {
  const _ScanView();

  Future<void> _go(BuildContext context, Future<void> Function() action) async {
    final vm = context.read<ReceiptScanViewModel>();
    await action();
    if (!context.mounted || vm.step != ScanStep.review) return;
    final report = await Navigator.push<ReceiptReport>(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(value: vm, child: const ReceiptValidationScreen()),
      ),
    );
    if (!context.mounted) return;
    if (report == null) {
      vm.reset();
      return;
    }
    if (report.reconciliation != null) {
      // Liste ciblée : écran résumé du rapprochement (achetés / oubliés / hors liste).
      await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => ReconciliationScreen(report: report)));
    } else {
      await showReceiptReport(context, report);
    }
    if (context.mounted) Navigator.pop(context, report);
  }

  /// Scan en direct, puis validation (ou bascule vers la galerie / la saisie).
  Future<void> _live(BuildContext context) async {
    final vm = context.read<ReceiptScanViewModel>();
    final out = await Navigator.push<LiveScanOutcome>(
      context,
      MaterialPageRoute(builder: (_) => const LiveReceiptScanScreen()),
    );
    if (out == null || !context.mounted) return;
    switch (out.kind) {
      case LiveOutcomeKind.done:
        await _go(context, () => vm.fromLive(out));
      case LiveOutcomeKind.manual:
        await _go(context, vm.manual);
      case LiveOutcomeKind.gallery:
        await _go(context, () => vm.capture(PhotoSource.gallery));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReceiptScanViewModel>();
    final busy = vm.step == ScanStep.capturing || vm.step == ScanStep.reading;
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner un ticket')),
      body: busy
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(vm.step == ScanStep.reading ? 'Lecture du ticket…' : 'Ouverture de l\'appareil photo…'),
              ]),
            )
          : ListView(padding: const EdgeInsets.all(20), children: [
              Icon(Icons.receipt_long, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                vm.ocrEnabled
                    ? 'Filmez votre ticket de caisse : les articles, les prix et le total sont lus en direct '
                        'et la somme est vérifiée. Vous n\'aurez qu\'à valider.'
                    : 'Photographiez votre ticket de caisse pour le joindre, puis saisissez ses lignes.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Conseil : ticket bien à plat, éclairé, cadré du nom du magasin jusqu\'au total.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (!vm.ocrEnabled)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Lecture automatique désactivée'),
                    subtitle: Text('La photo sera jointe, les lignes sont à saisir (Réglages).'),
                  ),
                ),
              if (vm.error != null)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(leading: const Icon(Icons.error_outline), title: Text(vm.error!)),
                ),
              const SizedBox(height: 24),
              // Lecture automatique activée : scan en direct proposé en premier.
              if (vm.ocrEnabled) ...[
                FilledButton.icon(
                  onPressed: () => _live(context),
                  icon: const Icon(Icons.document_scanner),
                  label: const Text('Scanner en direct'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
                const SizedBox(height: 12),
              ],
              (vm.ocrEnabled ? OutlinedButton.icon : FilledButton.icon)(
                onPressed: () => _go(context, () => vm.capture(PhotoSource.camera)),
                icon: const Icon(Icons.photo_camera),
                label: const Text('Prendre le ticket en photo'),
                style: (vm.ocrEnabled ? OutlinedButton.styleFrom : FilledButton.styleFrom)(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _go(context, () => vm.capture(PhotoSource.gallery)),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choisir une photo'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => _go(context, vm.manual),
                icon: const Icon(Icons.keyboard),
                label: const Text('Saisir le ticket à la main'),
              ),
            ]),
    );
  }
}

/// Écran « Validation des lignes ».
class ReceiptValidationScreen extends StatelessWidget {
  const ReceiptValidationScreen({super.key});

  Future<void> _save(BuildContext context) async {
    final vm = context.read<ReceiptScanViewModel>();
    final report = await vm.save();
    if (report != null && context.mounted) Navigator.pop(context, report);
  }

  Future<void> _editTotal(BuildContext context) async {
    final vm = context.read<ReceiptScanViewModel>();
    final d = vm.draft!;
    final v = await promptText(
      context,
      title: 'Total du ticket',
      label: 'Total (DT) — vide = somme des lignes',
      initial: d.readTotal == null ? '' : formatDt(d.readTotal!, symbol: false),
    );
    if (v == null) return;
    vm.setReadTotal(v.trim().isEmpty ? null : parseNumber(v));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReceiptScanViewModel>();
    final d = vm.draft;
    if (d == null) return const Scaffold(body: SizedBox.shrink());
    final saving = vm.step == ScanStep.saving;
    final knownStore = vm.stores.any((s) => s.id == d.storeId);
    return Scaffold(
      appBar: AppBar(title: const Text('Validation du ticket')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 100), children: [
        if (d.photo != null) ...[
          ExpansionTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Photo du ticket'),
            children: [ReceiptPhoto(d.photo, height: 320)],
          ),
        ],
        if (d.ocrText != null)
          ExpansionTile(
            leading: const Icon(Icons.text_snippet_outlined),
            title: const Text('Texte lu'),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(d.ocrText!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ],
          ),
        if (vm.error != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(leading: const Icon(Icons.warning_amber), title: Text(vm.error!)),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              DropdownButtonFormField<int?>(
                isExpanded: true,
                initialValue: knownStore ? d.storeId : null,
                decoration: const InputDecoration(labelText: 'Magasin', prefixIcon: Icon(Icons.storefront)),
                items: [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text(
                      !knownStore && d.storeName != null ? 'Autre : ${d.storeName}' : 'Autre / inconnu',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final s in vm.stores) DropdownMenuItem<int?>(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (id) async {
                  if (id != null) {
                    vm.setStore(vm.stores.firstWhere((s) => s.id == id));
                  } else {
                    final name = await promptText(context, title: 'Nom du magasin', initial: d.storeName ?? '');
                    if (name != null) vm.setStoreName(name);
                  }
                },
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: d.date,
                        firstDate: DateTime(2020),
                        lastDate: vm.service.now,
                      );
                      if (picked != null) vm.setDate(picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Date', prefixIcon: Icon(Icons.event)),
                      child: Text(formatDate(d.date)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                isExpanded: true,
                initialValue: vm.lists.any((l) => l.id == d.listId) ? d.listId : null,
                decoration: const InputDecoration(
                  labelText: 'Rapprocher avec la liste',
                  prefixIcon: Icon(Icons.checklist),
                  helperText: 'Les articles achetés seront cochés tout seuls.',
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Aucune')),
                  for (final l in vm.lists) DropdownMenuItem<int?>(value: l.id, child: Text(l.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: vm.setList,
              ),
            ]),
          ),
        ),
        if (d.lines.any(vm.isDoubtful))
          Card(
            color: Colors.orange.withValues(alpha: 0.12),
            child: ListTile(
              leading: Icon(Icons.help_outline, color: Colors.orange.shade800),
              title: Text(
                '${plural(d.lines.where(vm.isDoubtful).length, 'ligne')} à vérifier, en orange',
                style: TextStyle(color: Colors.orange.shade900),
              ),
              subtitle: const Text('Lecture peu sûre : touchez une ligne pour la corriger.'),
            ),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(d.lines.isEmpty ? 'Aucune ligne' : plural(d.lines.length, 'ligne'), style: Theme.of(context).textTheme.titleMedium)),
          TextButton.icon(
            onPressed: () async {
              final l = await editReceiptLine(context);
              if (l != null) await vm.putLine(null, l);
            },
            icon: const Icon(Icons.add),
            label: const Text('Ajouter une ligne'),
          ),
        ]),
        for (var i = 0; i < d.lines.length; i++)
          Dismissible(
            key: ObjectKey(d.lines[i]),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red.shade400,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (_) => vm.removeLine(i),
            child: _ValidationLine(
              line: d.lines[i],
              doubtful: vm.isDoubtful(d.lines[i]),
              onEdit: () async {
                final l = await editReceiptLine(context, line: d.lines[i]);
                if (l != null) await vm.putLine(i, l);
              },
              onDelete: () => vm.removeLine(i),
            ),
          ),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            ListTile(dense: true, title: const Text('Somme des lignes'), trailing: Text(formatDt(d.linesSum))),
            ListTile(
              dense: true,
              title: const Text('Total lu sur le ticket'),
              subtitle: d.readTotal == null ? const Text('Non trouvé : la somme des lignes sera utilisée') : null,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(d.readTotal == null ? '—' : formatDt(d.readTotal!)),
                const SizedBox(width: 4),
                const Icon(Icons.edit, size: 16),
              ]),
              onTap: () => _editTotal(context),
            ),
            if (!d.isConsistent)
              ListTile(
                dense: true,
                leading: Icon(Icons.warning_amber, color: Colors.orange.shade800),
                title: Text(
                  'Écart de ${formatDt((d.readTotal! - d.linesSum).abs())} : une ligne a peut-être été mal lue.',
                  style: TextStyle(color: Colors.orange.shade900),
                ),
              ),
          ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: saving ? null : () => _save(context),
            icon: saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text('Valider le ticket · ${formatDt(d.total)}'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ),
      ),
    );
  }
}

/// Une ligne du ticket à valider : touchée pour la modifier (libellé,
/// quantité, prix), corbeille pour la supprimer, orange si la lecture est
/// douteuse.
class _ValidationLine extends StatelessWidget {
  const _ValidationLine({required this.line, required this.doubtful, required this.onEdit, required this.onDelete});
  final ReceiptLine line;
  final bool doubtful;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final orange = Colors.orange.shade800;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: doubtful ? Colors.orange.withValues(alpha: 0.1) : null,
      shape: doubtful
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: orange))
          : null,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 16, right: 4),
        leading: doubtful ? Icon(Icons.help_outline, color: orange) : null,
        title: Text(line.label, style: doubtful ? TextStyle(color: orange) : null),
        subtitle: Text([
          if (doubtful) 'à vérifier',
          if (line.quantity != 1) '${formatQuantity(line.quantity, null)} × ${formatDt(line.unitPrice)}',
          line.category ?? '',
          if (line.productId != null) 'produit reconnu',
        ].where((s) => s.isNotEmpty).join(' · ')),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(
            formatDt(line.price),
            style: TextStyle(fontWeight: FontWeight.bold, color: line.price < 0 ? Colors.green.shade700 : null),
          ),
          IconButton(
            tooltip: 'Supprimer la ligne',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
            onPressed: onDelete,
          ),
        ]),
        onTap: onEdit,
      ),
    );
  }
}

/// Bilan après validation : articles cochés, oubliés, hors liste, budget et
/// hausses de prix.
Future<void> showReceiptReport(BuildContext context, ReceiptReport r) => showDialog<void>(
      context: context,
      builder: (c) {
        return AlertDialog(
          title: const Text('Ticket enregistré'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (r.checkedLabels.isNotEmpty) ...[
                _ReportSection(Icons.check_circle, Colors.green.shade600, plural(r.checkedLabels.length, 'article coché', 'articles cochés'),
                    r.checkedLabels),
              ],
              if (r.forgottenLabels.isNotEmpty)
                _ReportSection(Icons.report_problem, Colors.orange.shade800, 'Oubliés en magasin', r.forgottenLabels),
              if (r.unplannedLabels.isNotEmpty)
                _ReportSection(Icons.add_shopping_cart, Colors.blueGrey, 'Achats hors liste', r.unplannedLabels),
              ReceiptReportExtras(report: r),
            ]),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        );
      },
    );

/// Budget, hausses de prix et avertissements après l'enregistrement d'un
/// ticket (dialogue de bilan et écran de rapprochement).
class ReceiptReportExtras extends StatelessWidget {
  const ReceiptReportExtras({super.key, required this.report});
  final ReceiptReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final c = context;
    final budget = r.budget;
    final level = budget?.snapshot.level ?? BudgetLevel.none;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (budget != null && budget.snapshot.budget != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.account_balance_wallet,
                color: budgetColor(c, level, forecast: budget.snapshot.forecastOverrun)),
            const SizedBox(width: 8),
            Expanded(child: Text(budget.message)),
          ]),
        ),
      for (final a in r.priceAlerts)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.trending_up, color: Colors.red.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${a.label} : ${formatPct(a.increase)} '
                  '(${formatDt(a.lastPrice)} contre ${formatDt(a.average)} en moyenne).'),
            ),
          ]),
        ),
      for (final w in r.warnings)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(w, style: const TextStyle(fontSize: 12))),
    ]);
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection(this.icon, this.color, this.title, this.labels);
  final IconData icon;
  final Color color;
  final String title;
  final List<String> labels;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(labels.join(', ')),
            ]),
          ),
        ]),
      );
}
