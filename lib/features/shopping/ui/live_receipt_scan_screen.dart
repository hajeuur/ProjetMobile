import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../logic/live_scan_tracker.dart';
import '../models/dates.dart';
import '../services/shopping_devices.dart';
import '../viewmodels/live_scan_view_model.dart';

/// Scan en direct du ticket : la caméra lit le texte en continu (sans
/// bouton photo), les lignes reconnues s'allument sur l'aperçu et se
/// rangent dans « Lignes lues » ; la somme est comparée au total en direct.
///
/// Renvoie un [LiveScanOutcome] : lignes lues (avec la photo du ticket),
/// ou bascule vers la saisie manuelle / une photo de la galerie.
class LiveReceiptScanScreen extends StatefulWidget {
  const LiveReceiptScanScreen({super.key});

  @override
  State<LiveReceiptScanScreen> createState() => _LiveReceiptScanScreenState();
}

class _LiveReceiptScanScreenState extends State<LiveReceiptScanScreen> with WidgetsBindingObserver {
  late final LiveScanViewModel _vm = LiveScanViewModel(
    context.read<LiveCameraFactory>()(),
    onStable: HapticFeedback.mediumImpact,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Portrait : l'orientation de l'image lue reste celle du capteur.
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    _vm.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Caméra libérée en arrière-plan, rouverte au retour.
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _vm.pause();
    } else if (state == AppLifecycleState.resumed) {
      _vm.resume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(const []);
    _vm.dispose(); // arrête le flux et libère la caméra
    super.dispose();
  }

  Future<void> _finish() async {
    final out = await _vm.finish();
    if (out != null && mounted) Navigator.pop(context, out);
  }

  void _manual() => Navigator.pop(context, const LiveScanOutcome.manual());

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
        value: _vm,
        child: Consumer<LiveScanViewModel>(
          builder: (context, vm, _) => Scaffold(
            backgroundColor: Colors.black,
            body: vm.phase == LivePhase.error
                ? _CameraErrorView(vm: vm, onManual: _manual)
                : Column(children: [
                    Expanded(child: _CameraArea(vm: vm, onManual: _manual)),
                    _LinesPanel(vm: vm, onFinish: _finish, onManual: _manual),
                  ]),
          ),
        ),
      );
}

// ------------------------------------------------------------- Aperçu

class _CameraArea extends StatelessWidget {
  const _CameraArea({required this.vm, required this.onManual});
  final LiveScanViewModel vm;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final starting = vm.phase == LivePhase.starting;
    return Stack(fit: StackFit.expand, children: [
      if (!starting) vm.camera.buildPreview(_Highlights(vm.tracker.highlights, fresh: vm.fresh)),
      const IgnorePointer(child: CustomPaint(painter: _GuidePainter())),
      if (starting)
        const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 12),
            Text('Ouverture de la caméra…', style: TextStyle(color: Colors.white)),
          ]),
        ),
      SafeArea(
        child: Column(children: [
          Row(children: [
            IconButton(
              tooltip: 'Fermer',
              color: Colors.white,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.maybePop(context),
            ),
            const Expanded(
              child: Text(
                'Scan en direct',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: vm.torch ? 'Éteindre la lampe' : 'Allumer la lampe',
              color: Colors.white,
              icon: Icon(vm.torch ? Icons.flashlight_off : Icons.flashlight_on),
              onPressed: starting ? null : vm.toggleTorch,
            ),
          ]),
          if (!starting) _HintBanner(vm: vm),
          const Spacer(),
          if (vm.illegible) _IllegibleCard(vm: vm, onManual: onManual),
          if (vm.phase == LivePhase.finishing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Chip(
                avatar: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                label: Text('Photo du ticket…'),
              ),
            ),
        ]),
      ),
    ]);
  }
}

/// Cadre guide : assombrit l'extérieur, coins blancs.
class _GuidePainter extends CustomPainter {
  const _GuidePainter();

  static Rect frameFor(Size s) => Rect.fromLTRB(s.width * 0.07, s.height * 0.14, s.width * 0.93, s.height * 0.94);

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(frameFor(size), const Radius.circular(16));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(r)),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 28.0;
    final f = r.outerRect;
    for (final (c, dx, dy) in [
      (f.topLeft, 1.0, 1.0),
      (f.topRight, -1.0, 1.0),
      (f.bottomLeft, 1.0, -1.0),
      (f.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(c, c + Offset(l * dx, 0), p);
      canvas.drawLine(c, c + Offset(0, l * dy), p);
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) => false;
}

/// Surbrillance des lignes reconnues sur l'image courante.
class _Highlights extends StatelessWidget {
  const _Highlights(this.highlights, {required this.fresh});
  final List<LiveHighlight> highlights;
  final Set<int> fresh;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => Stack(children: [
          for (final h in highlights)
            AnimatedPositioned(
              key: ValueKey(h.isTotal ? 'total' : h.id),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              left: (h.box.left * c.maxWidth) - 4,
              top: (h.box.top * c.maxHeight) - 3,
              width: h.box.width * c.maxWidth + 8,
              height: h.box.height * c.maxHeight + 6,
              child: _HighlightBox(
                color: h.isTotal
                    ? Colors.lightBlueAccent
                    : h.doubtful
                        ? Colors.orange
                        : Colors.greenAccent,
              ),
            ),
        ]),
      );
}

class _HighlightBox extends StatelessWidget {
  const _HighlightBox({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        // Joue une seule fois, à l'apparition de la ligne.
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
        builder: (_, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.22),
            border: Border.all(color: color, width: 3),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      );
}

class _HintBanner extends StatelessWidget {
  const _HintBanner({required this.vm});
  final LiveScanViewModel vm;

  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = switch (vm.hint) {
      LiveHint.tooDark => (Icons.wb_sunny_outlined, 'Trop sombre : Rapproche-toi / ajoute de la lumière', Colors.orange.shade800),
      LiveHint.tooFar => (Icons.zoom_in, 'Texte trop petit : rapproche-toi du ticket', Colors.orange.shade800),
      LiveHint.aim => (Icons.crop_free, 'Placez le ticket dans le cadre, bien à plat', Colors.black54),
      LiveHint.none when vm.isStable => (Icons.check_circle, 'Lecture stable : vous pouvez terminer', Colors.green.shade700),
      LiveHint.none => (Icons.document_scanner_outlined, 'Lecture en cours… faites glisser le long du ticket', Colors.black54),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey(text),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: const TextStyle(color: Colors.white))),
        ]),
      ),
    );
  }
}

class _IllegibleCard extends StatelessWidget {
  const _IllegibleCard({required this.vm, required this.onManual});
  final LiveScanViewModel vm;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.blur_on, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Text('Ticket illisible', style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 6),
            Text(
              vm.hint == LiveHint.tooDark
                  ? 'L\'image est trop sombre. Rapproche-toi / ajoute de la lumière, ou allumez la lampe.'
                  : 'Aucune ligne de prix reconnue. Tenez le téléphone bien droit au-dessus du ticket, '
                      'à plat et éclairé, ou saisissez-le à la main.',
            ),
            Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
              TextButton(onPressed: onManual, child: const Text('Saisir à la main')),
              FilledButton.tonal(onPressed: vm.restartReading, child: const Text('Réessayer')),
            ]),
          ]),
        ),
      );
}

// ------------------------------------------------------ Lignes lues

class _LinesPanel extends StatelessWidget {
  const _LinesPanel({required this.vm, required this.onFinish, required this.onManual});
  final LiveScanViewModel vm;
  final VoidCallback onFinish;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = vm.tracker;
    final lines = t.lines;
    final height = (MediaQuery.sizeOf(context).height * 0.4).clamp(260.0, 380.0);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
            child: Row(children: [
              Expanded(
                child: Text(
                  'Lignes lues (${lines.length})',
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: _TotalChip(tracker: t)),
            ]),
          ),
          Expanded(
            child: lines.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Les lignes du ticket apparaîtront ici au fur et à mesure de la lecture.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: lines.length,
                    itemBuilder: (_, i) => _LineTile(key: ValueKey(lines[i].id), line: lines[i]),
                  ),
          ),
          if (t.total != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Somme des lignes : ${formatDt(t.linesSum)} · Total ticket : ${formatDt(t.total!)}',
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(children: [
              Flexible(
                child: TextButton.icon(
                  onPressed: onManual,
                  icon: const Icon(Icons.keyboard),
                  label: const Text('À la main', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: _FinishButton(vm: vm, onFinish: onFinish)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _FinishButton extends StatelessWidget {
  const _FinishButton({required this.vm, required this.onFinish});
  final LiveScanViewModel vm;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final enabled = vm.canFinish;
    // Texte stable : le bouton grossit légèrement pour proposer de terminer.
    return AnimatedScale(
      scale: vm.isStable ? 1.04 : 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      child: vm.isStable
          ? FilledButton.icon(
              onPressed: enabled ? onFinish : null,
              icon: const Icon(Icons.check),
              label: const Text('Terminer le scan', maxLines: 1, overflow: TextOverflow.ellipsis),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            )
          : OutlinedButton.icon(
              onPressed: enabled ? onFinish : null,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Terminer le scan', maxLines: 1, overflow: TextOverflow.ellipsis),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
    );
  }
}

/// « Total validé » en vert, « Écart de X DT » en orange.
class _TotalChip extends StatelessWidget {
  const _TotalChip({required this.tracker});
  final LiveScanTracker tracker;

  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = switch (tracker.totalCheck) {
      TotalCheck.valid => (Icons.verified, 'Total validé', Colors.green.shade700),
      TotalCheck.gap => (Icons.warning_amber, 'Écart de ${formatDt(tracker.gap.abs())}', Colors.orange.shade800),
      TotalCheck.missing => (Icons.hourglass_empty, 'Total non lu', Colors.blueGrey),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey(text),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({super.key, required this.line});
  final TrackedLine line;

  @override
  Widget build(BuildContext context) {
    final doubtful = line.isDoubtful;
    final color = doubtful ? Colors.orange.shade800 : null;
    // Apparition : glisse depuis la droite en fondu (une seule fois par ligne).
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(24 * (1 - t), 0), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: doubtful ? Colors.orange.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(doubtful ? Icons.help_outline : Icons.check_circle_outline,
              color: doubtful ? color : Colors.green.shade600, size: 20),
          title: Text(line.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color)),
          subtitle: Text(
            [
              if (line.quantity != 1) '${formatQuantity(line.quantity, null)} ×',
              doubtful ? 'à vérifier' : 'confiance ${(line.confidence * 100).round()} %',
            ].join(' · '),
            style: TextStyle(color: color),
          ),
          trailing: Text(
            formatDt(line.price),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color ?? (line.price < 0 ? Colors.green.shade700 : null),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ Erreurs

class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({required this.vm, required this.onManual});
  final LiveScanViewModel vm;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final e = vm.error ?? LiveCameraError.failed;
    final (title, message) = switch (e) {
      LiveCameraError.permissionDenied => (
          'Accès à la caméra refusé',
          'PanierMalin a besoin de la caméra pour lire le ticket en direct. Seule la photo du ticket '
              'que vous validez est conservée, sur le téléphone.',
        ),
      LiveCameraError.permissionPermanentlyDenied => (
          'Caméra bloquée',
          'L\'accès à la caméra a été refusé définitivement. Autorisez-le dans les réglages du téléphone : '
              'Applications › PanierMalin › Autorisations › Caméra.',
        ),
      LiveCameraError.noCamera => ('Aucune caméra', 'Cet appareil n\'a pas de caméra arrière.'),
      LiveCameraError.failed => (
          'Caméra indisponible',
          'La caméra n\'a pas pu démarrer (elle est peut-être utilisée par une autre application).',
        ),
    };
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(tooltip: 'Fermer', icon: const Icon(Icons.close), onPressed: () => Navigator.maybePop(context)),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.no_photography_outlined, size: 56, color: theme.colorScheme.error),
                  const SizedBox(height: 12),
                  Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  if (e == LiveCameraError.permissionPermanentlyDenied)
                    FilledButton.icon(
                      onPressed: vm.camera.openSettings,
                      icon: const Icon(Icons.settings),
                      label: const Text('Ouvrir les réglages'),
                    ),
                  if (e != LiveCameraError.noCamera)
                    FilledButton.tonalIcon(onPressed: vm.start, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, const LiveScanOutcome.gallery()),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choisir une photo'),
                  ),
                  TextButton.icon(onPressed: onManual, icon: const Icon(Icons.keyboard), label: const Text('Saisir à la main')),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
