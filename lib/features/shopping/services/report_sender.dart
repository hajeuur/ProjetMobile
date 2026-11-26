import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/budget_report.dart';

/// Issue d'un envoi.
enum SendOutcome {
  /// Partagé (une application a été choisie).
  sent,

  /// Partagé, mais le système ne dit pas si l'utilisateur est allé au bout.
  probablySent,

  /// Feuille de partage fermée sans choisir : rien n'est compté.
  cancelled,

  /// Aucune application capable de recevoir le fichier.
  noApp,
  failed,
}

class SendResult {
  const SendResult(this.outcome, [this.error]);
  final SendOutcome outcome;
  final String? error;

  bool get counted => outcome == SendOutcome.sent || outcome == SendOutcome.probablySent;
}

/// Envoi du rapport. Une seule implémentation aujourd'hui (feuille de partage
/// du système) ; l'interface permet d'en ajouter (e-mail, Drive…) sans
/// toucher aux écrans.
abstract class ReportSender {
  Future<SendResult> send(File pdf, {required String message, String? subject});
}

/// Feuille de partage (share_plus) : le PDF en pièce jointe et le message
/// pré-rempli ; l'utilisateur choisit WhatsApp, SMS, e-mail…
class ShareSheetReportSender implements ReportSender {
  const ShareSheetReportSender();

  @override
  Future<SendResult> send(File pdf, {required String message, String? subject}) async {
    try {
      final r = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(pdf.path, mimeType: 'application/pdf')],
          text: message,
          subject: subject,
        ),
      );
      return SendResult(switch (r.status) {
        ShareResultStatus.success => SendOutcome.sent,
        ShareResultStatus.dismissed => SendOutcome.cancelled,
        ShareResultStatus.unavailable => SendOutcome.probablySent,
      });
    } on PlatformException catch (e) {
      // Android : ActivityNotFoundException quand rien ne peut recevoir un PDF.
      final noApp = '${e.code} ${e.message}'.toLowerCase().contains('activity');
      return SendResult(noApp ? SendOutcome.noApp : SendOutcome.failed, e.message);
    } on MissingPluginException {
      return const SendResult(SendOutcome.noApp, 'Partage indisponible sur cet appareil.');
    } catch (e) {
      return SendResult(SendOutcome.failed, '$e');
    }
  }
}

/// Espace de stockage insuffisant pour écrire le PDF.
class StorageFullException implements Exception {
  const StorageFullException();
  @override
  String toString() => 'Espace de stockage insuffisant : libère un peu de place puis réessaie.';
}

/// Fichiers PDF temporaires (dossier « rapports » du cache), effacés après
/// le partage — share_plus en garde sa propre copie le temps de l'envoi.
class ReportStorage {
  ReportStorage({Future<Directory> Function()? baseDir}) : _baseDir = baseDir ?? getTemporaryDirectory;
  final Future<Directory> Function() _baseDir;

  Future<Directory> _dir() async {
    final d = Directory('${(await _baseDir()).path}${Platform.pathSeparator}rapports');
    if (!d.existsSync()) await d.create(recursive: true);
    return d;
  }

  Future<File> write(String name, Uint8List bytes) async {
    final f = File('${(await _dir()).path}${Platform.pathSeparator}$name');
    try {
      await f.writeAsBytes(bytes, flush: true);
      return f;
    } on FileSystemException catch (e) {
      if (f.existsSync()) await f.delete();
      // ENOSPC = 28 (Linux / Android / iOS) ; 112 sous Windows.
      final code = e.osError?.errorCode;
      if (code == 28 || code == 112) throw const StorageFullException();
      rethrow;
    }
  }

  Future<void> delete(File f) async {
    try {
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  /// Supprime les rapports restés d'un envoi interrompu.
  Future<void> cleanup() async {
    try {
      for (final f in (await _dir()).listSync().whereType<File>()) {
        await f.delete();
      }
    } catch (_) {}
  }
}

/// Discussion WhatsApp du proche (wa.me, texte seulement), sinon SMS.
class ContactMessenger {
  const ContactMessenger();

  /// WhatsApp installé (requêtes déclarées dans AndroidManifest pour Android 11+).
  Future<bool> hasWhatsApp() async {
    try {
      return await canLaunchUrl(Uri.parse('whatsapp://send?text=test'));
    } catch (_) {
      return false;
    }
  }

  /// Ouvre la discussion du proche avec le message. Renvoie le canal utilisé,
  /// ou null si ni WhatsApp ni SMS ne sont disponibles.
  Future<String?> open(AlertContact contact, String message) async {
    final number = internationalNumber(contact.phone);
    if (number == null) return null;
    try {
      if (await hasWhatsApp() && await launchUrl(whatsAppLink(number, message), mode: LaunchMode.externalApplication)) {
        return 'WhatsApp';
      }
      // Espaces en %20 (et non « + ») : recommandé par url_launcher pour sms:.
      final sms = Uri(scheme: 'sms', path: '+$number', query: 'body=${Uri.encodeComponent(message)}');
      if (await canLaunchUrl(sms) && await launchUrl(sms)) return 'SMS';
    } catch (_) {}
    return null;
  }
}
