import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dates.dart';
import '../models/shopping_list.dart';
import '../services/shopping_service.dart';
import '../viewmodels/reconciliation_view_model.dart';
import 'receipt_scan_screen.dart' show ReceiptReportExtras;

/// Résumé après validation d'un ticket : « 6 achetés, 2 oubliés : lait,
/// pain ». Les articles achetés se cochent un à un (animation), les cas
/// incertains attendent un oui/non, chaque oublié peut être gardé pour la
/// prochaine liste, et les achats hors liste sont rappelés.
class ReconciliationScreen extends StatelessWidget {
  const ReconciliationScreen({super.key, required this.report});
  final ReceiptReport report;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => ReconciliationViewModel(context.read<ShoppingService>(), report.reconciliation!),
        child: _ReconciliationView(report: report),
      );
}

class _ReconciliationView extends StatelessWidget {
  const _ReconciliationView({required this.report});
  final ReceiptReport report;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReconciliationViewModel>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Rapprochement avec la liste')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        // En-tête : le bilan en une phrase.
        Card(
          color: vm.forgotten.isEmpty && vm.pending.isEmpty
              ? Color.alphaBlend(Colors.green.withValues(alpha: 0.18), theme.colorScheme.surface)
              : theme.colorScheme.secondaryContainer,
          child: ListTile(
            leading: Icon(
              vm.forgotten.isEmpty && vm.pending.isEmpty ? Icons.emoji_events : Icons.fact_check,
              color: vm.forgotten.isEmpty && vm.pending.isEmpty ? Colors.green.shade700 : null,
              size: 32,
            ),
            title: Text(vm.headline, style: theme.textTheme.titleMedium),
            subtitle: Text('Liste « ${vm.listName} »'),
          ),
        ),
        if (vm.error != null)
          Card(
            color: theme.colorScheme.errorContainer,
            child: ListTile(leading: const Icon(Icons.error_outline), title: Text(vm.error!)),
          ),

        if (vm.pending.isNotEmpty) ...[
          _SectionTitle(Icons.help_outline, 'À confirmer (${vm.pending.length})', Colors.orange.shade800),
          for (final m in vm.pending) _PendingCard(m),
        ],

        _SectionTitle(Icons.check_circle, 'Achetés (${vm.purchased.length})', Colors.green.shade700),
        if (vm.purchased.isEmpty)
          const Padding(padding: EdgeInsets.all(8), child: Text('Aucun article de la liste trouvé sur ce ticket.')),
        for (var i = 0; i < vm.purchased.length; i++)
          _AnimatedCheckRow(key: ValueKey(vm.purchased[i].itemId), match: vm.purchased[i], order: i),

        if (vm.forgotten.isNotEmpty) ...[
          _SectionTitle(Icons.report_problem, 'Oubliés (${vm.forgotten.length})', Colors.orange.shade800),
          for (final item in vm.forgotten) _ForgottenCard(item),
          if (vm.forgotten.where((i) => !vm.kept.contains(i.id)).length > 1)
            FilledButton.tonalIcon(
              onPressed: vm.busy ? null : vm.keepAll,
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('Tout garder pour la prochaine liste'),
            ),
          if (vm.kept.isNotEmpty && vm.nextListName != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${plural(vm.kept.length, 'article reporté', 'articles reportés')} dans « ${vm.nextListName} ».',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],

        if (vm.unplanned.isNotEmpty) ...[
          _SectionTitle(Icons.add_shopping_cart, 'Achats hors liste (${vm.unplanned.length})', Colors.blueGrey),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final l in vm.unplanned) Chip(label: Text(l), visualDensity: VisualDensity.compact),
          ]),
        ],

        const SizedBox(height: 16),
        ReceiptReportExtras(report: report),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.done),
            label: Text(vm.pending.isEmpty ? 'Terminer' : 'Terminer sans répondre'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.icon, this.text, this.color);
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color))),
        ]),
      );
}

/// Article oublié, avec « Garder pour la prochaine liste ».
class _ForgottenCard extends StatelessWidget {
  const _ForgottenCard(this.item);
  final ShoppingItem item;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReconciliationViewModel>();
    final kept = vm.kept.contains(item.id);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4, right: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          ListTile(
            leading: Icon(Icons.remove_shopping_cart, color: Colors.orange.shade800),
            title: Text(item.label),
            subtitle: item.quantityText.isEmpty ? null : Text(item.quantityText),
            trailing: kept ? Icon(Icons.bookmark_added, color: Colors.green.shade600) : null,
          ),
          kept
              ? TextButton.icon(
                  onPressed: vm.busy ? null : () => vm.unkeep(item),
                  icon: const Icon(Icons.undo, size: 18),
                  label: Text('Gardé pour « ${vm.nextListName ?? ShoppingService.nextListName} » · annuler'),
                )
              : OutlinedButton.icon(
                  onPressed: vm.busy ? null : () => vm.keep(item),
                  icon: const Icon(Icons.playlist_add, size: 18),
                  label: const Text('Garder pour la prochaine liste'),
                ),
        ]),
      ),
    );
  }
}

/// Rapprochement incertain : « « JUS POMME 1L » = « Jus d'orange » ? » Oui / Non.
class _PendingCard extends StatelessWidget {
  const _PendingCard(this.m);
  final PendingMatch m;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<ReconciliationViewModel>();
    final busy = context.select<ReconciliationViewModel, bool>((v) => v.busy);
    return Card(
      color: Colors.orange.withValues(alpha: 0.08),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Sur le ticket, « '),
            TextSpan(text: m.lineLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
            const TextSpan(text: ' », est-ce votre « '),
            TextSpan(text: m.itemLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
            const TextSpan(text: ' » ?'),
          ])),
          Text('Ressemblance ${(m.score * 100).round()} %', style: Theme.of(context).textTheme.bodySmall),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: busy ? null : () => vm.answer(m, yes: false), child: const Text('Non')),
            const SizedBox(width: 8),
            FilledButton(onPressed: busy ? null : () => vm.answer(m, yes: true), child: const Text('Oui')),
          ]),
        ]),
      ),
    );
  }
}

/// Article acheté : la case se coche toute seule, les unes après les autres.
class _AnimatedCheckRow extends StatelessWidget {
  const _AnimatedCheckRow({super.key, required this.match, required this.order});
  final PurchasedMatch match;
  final int order;

  @override
  Widget build(BuildContext context) {
    final delay = 150 * order.clamp(0, 12);
    final total = 450 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOut),
      builder: (context, t, _) {
        final done = t > 0.5;
        final green = Colors.green.shade600;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 3),
          child: ListTile(
            dense: true,
            leading: Transform.scale(
              scale: done ? 1 + 0.3 * (1 - t) * 2 : 1, // petit rebond au moment de cocher
              child: Icon(
                done ? Icons.check_box : Icons.check_box_outline_blank,
                color: done ? green : Theme.of(context).colorScheme.outline,
                semanticLabel: done ? 'coché' : null,
              ),
            ),
            title: Text(
              match.itemLabel,
              style: TextStyle(
                decoration: done ? TextDecoration.lineThrough : null,
                color: done ? Colors.grey.shade600 : null,
              ),
            ),
            subtitle: Text('ticket : ${match.lineLabel}', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        );
      },
    );
  }
}
