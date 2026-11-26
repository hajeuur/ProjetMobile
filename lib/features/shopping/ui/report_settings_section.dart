import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/budget_report.dart';
import '../models/dates.dart';
import '../services/shopping_service.dart';
import 'report_preview_screen.dart';

/// Réglages « Alerte budget par rapport PDF » : interrupteur, proche à
/// prévenir (avec son accord), seuils, confidentialité, rapport test,
/// historique des envois.
class ReportSettingsSection extends StatefulWidget {
  const ReportSettingsSection({super.key});

  @override
  State<ReportSettingsSection> createState() => _ReportSettingsSectionState();
}

class _ReportSettingsSectionState extends State<ReportSettingsSection> {
  late final ShoppingService _service = context.read<ShoppingService>();
  ReportSettings? _s;
  List<ReportSendRecord> _history = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await _service.reportSettings();
    final h = await _service.reportHistory();
    if (mounted) {
      setState(() {
        _s = s;
        _history = h;
      });
    }
  }

  Future<void> _save(ReportSettings s) async {
    setState(() => _s = s);
    await _service.saveReportSettings(s);
  }

  /// Saisie du proche ; renvoie false si annulée.
  Future<bool> _editContact() async {
    final r = await showDialog<({AlertContact? contact, bool removed})>(
      context: context,
      builder: (_) => _ContactDialog(initial: _s!.contact, now: _service.now),
    );
    if (r == null) return false;
    if (r.removed) {
      await _save(_s!.copyWith(clearContact: true, enabled: false));
      return false;
    }
    await _save(_s!.copyWith(contact: r.contact));
    return true;
  }

  Future<void> _toggle(bool on) async {
    if (on && _s!.contact == null && !await _editContact()) return; // pas de proche : reste désactivé
    await _save(_s!.copyWith(enabled: on));
  }

  Future<void> _test() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportPreviewScreen(month: _service.now, reason: ReportReason.test, contact: _s!.contact),
      ),
    );
    await _load(); // historique
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final c = s.contact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ListTile(title: Text('Rapport PDF au proche')),
        SwitchListTile(
          secondary: const Icon(Icons.picture_as_pdf_outlined),
          title: const Text('Alerte budget par rapport PDF'),
          subtitle: const Text(
            'Au seuil ou au budget atteint, propose d\'envoyer le rapport du mois à un proche '
            '(WhatsApp, SMS, e-mail…). Rien ne part sans ta confirmation.',
          ),
          value: s.enabled && c != null,
          onChanged: _toggle,
        ),
        ListTile(
          contentPadding: const EdgeInsets.only(left: 72, right: 16),
          leading: Icon(c == null ? Icons.person_add_alt : Icons.contact_phone_outlined),
          title: Text(c == null ? 'Choisir le proche à prévenir' : 'Proche : ${c.name}'),
          subtitle: Text(
            c == null
                ? 'Nom, numéro et son accord.'
                : '${c.phone.isEmpty ? 'Sans numéro' : c.phone} · accord confirmé le ${formatDate(c.consentAt)}',
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: _editContact,
        ),
        CheckboxListTile(
          contentPadding: const EdgeInsets.only(left: 72, right: 16),
          title: const Text('Au seuil d\'alerte (80 %)'),
          value: s.atThreshold,
          onChanged: (v) => _save(s.copyWith(atThreshold: v ?? true)),
        ),
        CheckboxListTile(
          contentPadding: const EdgeInsets.only(left: 72, right: 16),
          title: const Text('Au budget atteint (100 %)'),
          value: s.atBudget,
          onChanged: (v) => _save(s.copyWith(atBudget: v ?? true)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.visibility_off_outlined),
          title: const Text('Masquer les montants'),
          subtitle: const Text('Seuls les pourcentages apparaissent dans le rapport et le message.'),
          value: s.maskAmounts,
          onChanged: (v) => _save(s.copyWith(maskAmounts: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.receipt_long_outlined),
          title: const Text('Inclure le détail des articles'),
          subtitle: const Text('Les articles de chaque ticket, sous le ticket.'),
          value: s.includeItems,
          onChanged: (v) => _save(s.copyWith(includeItems: v)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 4, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: _test,
              icon: const Icon(Icons.outgoing_mail),
              label: const Text('Envoyer un rapport test'),
            ),
          ),
        ),
        ExpansionTile(
          leading: const Icon(Icons.history),
          title: const Text('Historique des envois'),
          subtitle: Text(_history.isEmpty ? 'Aucun envoi pour l\'instant' : plural(_history.length, 'envoi')),
          children: [
            if (_history.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Les rapports envoyés apparaîtront ici (date, seuil, destinataire).',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            for (final h in _history)
              ListTile(
                dense: true,
                leading: Icon(h.confirmed ? Icons.check_circle_outline : Icons.help_outline),
                title: Text('${formatDate(h.date)} · ${h.reason.label}'),
                subtitle: Text(
                  '${h.recipient} · rapport de ${monthLabel(h.month)}'
                  '${h.confirmed ? '' : ' · envoi non confirmé par le téléphone'}',
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Nom, numéro et consentement explicite du proche.
class _ContactDialog extends StatefulWidget {
  const _ContactDialog({required this.initial, required this.now});
  final AlertContact? initial;
  final DateTime now;

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _phone = TextEditingController(text: widget.initial?.phone ?? '');
  late bool _consent = widget.initial != null;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _ok() {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Le prénom est nécessaire.');
    if (phone.isNotEmpty && internationalNumber(phone) == null) {
      return setState(() => _error = 'Numéro invalide (ex. 22 123 456 ou +216 22 123 456).');
    }
    if (!_consent) return setState(() => _error = 'Coche l\'accord du proche pour continuer.');
    Navigator.pop(context, (
      contact: AlertContact(name: name, phone: phone, consentAt: widget.initial?.consentAt ?? widget.now),
      removed: false,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final who = _name.text.trim().isEmpty ? 'ce proche' : _name.text.trim();
    return AlertDialog(
      title: const Text('Proche à prévenir'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Prénom ou nom (ex. Maman)'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Numéro (facultatif)',
                helperText: 'Pour ouvrir sa discussion WhatsApp ou SMS.',
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _consent,
              onChanged: (v) => setState(() => _consent = v ?? false),
              title: Text(
                '$who est d\'accord pour recevoir mes rapports de budget, et je choisis de lui '
                'partager mes dépenses.',
              ),
            ),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: [
        if (widget.initial != null)
          TextButton(
            onPressed: () => Navigator.pop(context, (contact: null, removed: true)),
            child: const Text('Retirer'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: _ok, child: const Text('Enregistrer')),
      ],
    );
  }
}
