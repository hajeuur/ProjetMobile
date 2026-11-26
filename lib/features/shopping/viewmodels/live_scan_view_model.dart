import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logic/live_receipt_parser.dart';
import '../logic/live_scan_tracker.dart';
import '../logic/receipt_parser.dart';
import '../services/shopping_devices.dart';

enum LivePhase { starting, scanning, error, finishing }

/// Conseil affiché au-dessus de l'aperçu.
enum LiveHint {
  none,

  /// Aucune ligne encore : viser le ticket.
  aim,

  /// Image trop sombre.
  tooDark,

  /// Du texte, mais trop petit pour être lu.
  tooFar,
}

/// Ce que l'écran de scan en direct renvoie.
enum LiveOutcomeKind { done, manual, gallery }

class LiveScanOutcome {
  const LiveScanOutcome.done({required ParsedReceipt this.receipt, this.photo, this.ocrText, this.doubtful = const {}})
      : kind = LiveOutcomeKind.done;
  const LiveScanOutcome.manual()
      : kind = LiveOutcomeKind.manual,
        receipt = null,
        photo = null,
        ocrText = null,
        doubtful = const {};
  const LiveScanOutcome.gallery()
      : kind = LiveOutcomeKind.gallery,
        receipt = null,
        photo = null,
        ocrText = null,
        doubtful = const {};

  final LiveOutcomeKind kind;
  final ParsedReceipt? receipt;
  final String? photo;
  final String? ocrText;

  /// Indices des lignes douteuses (affichées en orange à la validation).
  final Set<int> doubtful;
}

/// Scan en direct : lit chaque image du flux, suit les lignes d'une image à
/// l'autre, vérifie la somme avec le total et repère quand le texte est stable.
class LiveScanViewModel extends ChangeNotifier {
  LiveScanViewModel(
    this.camera, {
    this.onStable,
    DateTime Function()? clock,
    this.illegibleAfter = const Duration(seconds: 10),
  }) : _clock = clock ?? DateTime.now;

  final LiveReceiptCamera camera;
  final DateTime Function() _clock;

  /// Appelé quand le texte devient stable (retour haptique).
  final VoidCallback? onStable;

  /// Sans aucune ligne lue après ce délai, le ticket est déclaré illisible.
  final Duration illegibleAfter;

  /// En dessous, l'image est trop sombre (luminosité moyenne 0–1).
  static const darkBelow = 0.2;

  /// Hauteur relative moyenne des rangées en dessous de laquelle le texte est
  /// trop petit pour être lu.
  static const tooSmallBelow = 0.014;

  final _parser = const LiveReceiptParser();
  LiveScanTracker tracker = LiveScanTracker();
  LivePhase phase = LivePhase.starting;
  LiveCameraError? error;
  LiveHint hint = LiveHint.aim;
  bool illegible = false;
  bool torch = false;
  String? finishError;

  /// Lignes qui viennent d'apparaître (animation).
  Set<int> fresh = {};

  StreamSubscription<LiveFrame>? _sub;
  DateTime? _startedAt;
  int _darkFrames = 0;
  bool _stableNotified = false;
  bool _disposed = false;

  /// Ouverture en cours (la fenêtre de permission met l'app en pause puis la
  /// reprend : il ne faut pas ouvrir une seconde caméra en même temps).
  bool _opening = false;

  /// Caméra libérée par [pause], à rouvrir au retour.
  bool _paused = false;

  bool get isStable => tracker.isStable;
  bool get canFinish => tracker.lines.isNotEmpty && phase == LivePhase.scanning;

  Future<void> start() async {
    if (_opening) return;
    _opening = true;
    phase = LivePhase.starting;
    error = null;
    _notify();
    try {
      await camera.open();
    } on LiveCameraException catch (e) {
      debugPrint('Scan en direct : $e');
      error = e.error;
      phase = LivePhase.error;
      _notify();
      return;
    } catch (e) {
      debugPrint('Scan en direct : $e');
      error = LiveCameraError.failed;
      phase = LivePhase.error;
      _notify();
      return;
    } finally {
      _opening = false;
    }
    if (_disposed) {
      await camera.close();
      return;
    }
    phase = LivePhase.scanning;
    _startedAt ??= _clock();
    _notify();
    _sub = camera.frames().listen(addFrame, onError: (Object e) {
      debugPrint('Scan en direct : $e');
      error = LiveCameraError.failed;
      phase = LivePhase.error;
      _notify();
    });
  }

  /// Application en arrière-plan : la caméra est libérée.
  Future<void> pause() async {
    if (phase != LivePhase.scanning) return;
    await _sub?.cancel();
    _sub = null;
    torch = false;
    _paused = true;
    await camera.close();
    phase = LivePhase.starting;
    _notify();
  }

  Future<void> resume() async {
    if (!_paused || _disposed) return;
    _paused = false;
    await start();
  }

  /// Lecture d'une image du flux.
  void addFrame(LiveFrame f) {
    if (_disposed || phase != LivePhase.scanning) return;
    final reading = _parser.parse(f.rows);
    final confirmed = tracker.add(reading, rows: [for (final r in f.rows) r.text]);
    fresh = {for (final t in confirmed) t.id};

    final dark = f.brightness != null && f.brightness! < darkBelow;
    _darkFrames = dark ? _darkFrames + 1 : 0;
    final heights = [for (final r in f.rows) r.box.height];
    final small = heights.isNotEmpty && reading.lines.isEmpty && heights.reduce((a, b) => a + b) / heights.length < tooSmallBelow;
    hint = _darkFrames >= 2
        ? LiveHint.tooDark
        : small
            ? LiveHint.tooFar
            : tracker.lines.isEmpty
                ? LiveHint.aim
                : LiveHint.none;
    illegible = tracker.lines.isEmpty && _clock().difference(_startedAt ?? _clock()) >= illegibleAfter;

    if (tracker.isStable) {
      if (!_stableNotified) {
        _stableNotified = true;
        onStable?.call();
      }
    } else {
      _stableNotified = false;
    }
    _notify();
  }

  /// « Réessayer » après « Ticket illisible » : on repart de zéro.
  void restartReading() {
    tracker = LiveScanTracker();
    _startedAt = _clock();
    illegible = false;
    hint = LiveHint.aim;
    fresh = {};
    _stableNotified = false;
    _notify();
  }

  Future<void> toggleTorch() async {
    torch = !torch;
    _notify();
    await camera.setTorch(torch);
  }

  /// Termine le scan : photo du ticket conservée, lignes retenues.
  Future<LiveScanOutcome?> finish() async {
    if (!canFinish) return null;
    phase = LivePhase.finishing;
    finishError = null;
    _notify();
    await _sub?.cancel();
    _sub = null;
    String? photo;
    try {
      photo = await camera.takePhoto();
    } catch (e) {
      // Sans photo, les lignes lues restent valables.
      finishError = 'Photo du ticket impossible : elle ne sera pas jointe.';
      debugPrint('$e');
    }
    final t = tracker;
    final lines = t.lines;
    return LiveScanOutcome.done(
      receipt: ParsedReceipt(
        lines: [for (final l in lines) ParsedLine(label: l.label, quantity: l.quantity, price: l.price)],
        total: t.total ?? t.bestTotal,
        date: t.date,
        headerLines: t.headerLines,
      ),
      photo: photo,
      ocrText: t.bestRows.isEmpty ? null : t.bestRows.join('\n'),
      doubtful: {
        for (var i = 0; i < lines.length; i++)
          if (lines[i].confidence < LiveReceiptParser.doubtfulBelow) i,
      },
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    // Caméra libérée quand l'écran se ferme.
    camera.close();
    super.dispose();
  }
}
