import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../logic/budget_report.dart';
import '../models/dates.dart';
import '../services/report_builder.dart';
import '../services/report_sender.dart';
import '../services/shopping_service.dart';
import 'widgets.dart';

/// Aperçu du rapport du mois, puis « Envoyer » (feuille de partage avec le
/// PDF et le message pré-rempli) ou « Annuler ». Renvoie true si envoyé.
class ReportPreviewScreen extends StatefulWidget {
  const ReportPreviewScreen({
    super.key,
    required this.month,
    required this.reason,
    this.contact,
    this.sender = const ShareSheetReportSender(),
    this.storage,
    this.messenger = const ContactMessenger(),
    this.livePreview = true,
  });

  final DateTime month;
  final ReportReason reason;

  /// Proche destinataire (alerte, test) ; null pour un export libre.
  final AlertContact? contact;
  final ReportSender sender;
  final ReportStorage? storage;
  final ContactMessenger messenger;

  /// Aperçu des pages (désactivé dans les tests : pas de moteur d'impression).
  final bool livePreview;

  @override
  State<ReportPreviewScreen> createState() => _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends State<ReportPreviewScreen> {
  late final ShoppingService _service = context.read<ShoppingService>();
  late final ReportStorage _storage = widget.storage ?? ReportStorage();
  final _message = TextEditingController();
  Uint8List? _pdf;
  ReportContent? _content;
  DateTime? _month;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _storage.cleanup(); // rapports restés d'un envoi interrompu
    _build();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _build() async {
    setState(() => _error = null);
    try {
      final settings = await _service.reportSettings();
      final data = await _service.monthlyReport(widget.month);
      final content = buildReportContent(data, settings.options(widget.reason));
      final fonts = await ReportFonts.load();
      final pdf = await ReportBuilder(fonts).build(content);
      if (!mounted) return;
      setState(() {
        _content = content;
        _pdf = pdf;
        _month = data.month;
        _message.text = reportMessage(data, maskAmounts: settings.maskAmounts);
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Le rapport n\'a pas pu être préparé : $e');
    }
  }

  String get _who => widget.contact?.firstName ?? 'Partage';

  Future<void> _send() async {
    final pdf = _pdf;
    if (pdf == null || _sending) return;
    setState(() => _sending = true);
    File? file;
    try {
      file = await _storage.write(reportFileName(_month!), pdf);
      final r = await widget.sender.send(file, message: _message.text.trim(), subject: _content!.title);
      if (!mounted) return;
      switch (r.outcome) {
        case SendOutcome.sent:
        case SendOutcome.probablySent:
          await _service.recordReportSent(
            widget.reason,
            recipient: widget.contact?.name ?? 'Partage',
            month: _month!,
            confirmed: r.outcome == SendOutcome.sent,
          );
          if (!mounted) return;
          showSnack(context, 'Rapport partagé${widget.contact == null ? '' : ' pour ${widget.contact!.firstName}'}.');
          Navigator.pop(context, true);
        case SendOutcome.cancelled:
          showSnack(context, 'Envoi annulé : rien n\'a été envoyé ni compté.');
        case SendOutcome.noApp:
        case SendOutcome.failed:
          await _fallback(
            r.outcome == SendOutcome.noApp
                ? 'Aucune application ne peut recevoir le PDF sur ce téléphone.'
                : 'Le partage a échoué${r.error == null ? '' : ' (${r.error})'}.',
          );
      }
    } on StorageFullException catch (e) {
      if (mounted) await _fallback('$e');
    } catch (e) {
      if (mounted) await _fallback('Le partage a échoué : $e');
    } finally {
      if (mounted) setState(() => _sending = false);
      // share_plus a sa propre copie : le PDF temporaire est effacé en arrière-plan.
      if (file != null) unawaited(_storage.delete(file));
    }
  }

  /// Jamais d'impasse : imprimer / enregistrer le PDF, ou prévenir le proche
  /// par un simple message.
  Future<void> _fallback(String problem) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Envoi impossible'),
        content: Text(
          '$problem\n\nTu peux enregistrer le PDF (Imprimer → Enregistrer en PDF)'
          '${widget.contact == null ? '' : ' ou prévenir ${widget.contact!.firstName} par un message sans pièce jointe'}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
          if (widget.contact != null)
            TextButton(onPressed: () => Navigator.pop(ctx, 'message'), child: const Text('Message')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'print'), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'print') {
      try {
        await Printing.layoutPdf(onLayout: (_) async => _pdf!, name: reportFileName(_month!));
      } catch (e) {
        if (mounted) showSnack(context, 'Enregistrement indisponible : $e');
      }
    } else if (choice == 'message') {
      await _openChat();
    }
  }

  /// Discussion WhatsApp du proche (wa.me), sinon SMS : texte seulement.
  Future<void> _openChat() async {
    final c = widget.contact;
    if (c == null) return;
    final channel = await widget.messenger.open(c, _message.text.trim());
    if (!mounted) return;
    showSnack(
      context,
      channel == null
          ? 'Ni WhatsApp ni SMS disponibles, ou numéro invalide : vérifie le numéro dans les réglages.'
          : '$channel ouvert : le lien envoie le texte seulement, utilise « Envoyer » pour le PDF.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _content;
    return Scaffold(
      appBar: AppBar(title: Text(widget.reason == ReportReason.test ? 'Rapport test' : 'Aperçu du rapport')),
      body: _error != null
          ? EmptyState(
              icon: Icons.picture_as_pdf_outlined,
              title: 'Rapport indisponible',
              message: _error,
              action: FilledButton(onPressed: _build, child: const Text('Réessayer')),
            )
          : _pdf == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: widget.livePreview
                      ? PdfPreview(
                          build: (_) async => _pdf!,
                          useActions: false,
                          allowPrinting: false,
                          allowSharing: false,
                          canChangeOrientation: false,
                          canChangePageFormat: false,
                          canDebug: false,
                          pdfFileName: reportFileName(_month!),
                          onError: (_, e) => _Summary(content: c!, note: 'Aperçu des pages indisponible ($e).'),
                        )
                      : _Summary(content: c!),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: TextField(
                    controller: _message,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _pdf == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _sending ? null : () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                            child: const Text('Annuler'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _sending ? null : _send,
                            icon: _sending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.send),
                            label: Text(
                              widget.contact == null ? 'Partager' : 'Envoyer à $_who',
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                          ),
                        ),
                      ],
                    ),
                    if (widget.contact != null)
                      TextButton.icon(
                        onPressed: _sending ? null : _openChat,
                        icon: const Icon(Icons.chat_outlined, size: 18),
                        label: Text('Ouvrir la discussion de $_who (texte seul)', style: theme.textTheme.bodySmall),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Résumé lisible du rapport quand l'aperçu des pages n'est pas disponible.
class _Summary extends StatelessWidget {
  const _Summary({required this.content, this.note});
  final ReportContent content;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = switch (content.tone) {
      ReportTone.good => dark ? Colors.green.shade300 : Colors.green.shade800,
      ReportTone.caution => dark ? Colors.orange.shade300 : Colors.orange.shade800,
      ReportTone.over => dark ? Colors.red.shade300 : Colors.red.shade700,
    };
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (note != null) Text(note!, style: theme.textTheme.bodySmall),
        Text(content.title, style: theme.textTheme.titleMedium),
        Text(content.subtitle, style: theme.textTheme.bodySmall),
        if (content.testBanner != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              content.testBanner!,
              style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold),
            ),
          ),
        Card(
          color: color.withValues(alpha: 0.14),
          child: ListTile(
            leading: Text(
              content.headline,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color),
            ),
            title: Text(
              content.status,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        Wrap(spacing: 12, runSpacing: 4, children: [for (final m in content.metrics) Text('${m.label} : ${m.value}')]),
        const SizedBox(height: 8),
        for (final f in content.forecast) Text(f),
        const SizedBox(height: 8),
        Text(
          '${plural(content.tickets.length, 'ticket')} · ${plural(content.categories.length, 'catégorie')}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
