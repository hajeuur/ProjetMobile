import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/shopping_devices.dart';

/// Résultat de l'écoute : la phrase reconnue, ou la demande de passer à la
/// saisie manuelle.
class VoiceSheetResult {
  const VoiceSheetResult.text(this.text) : manual = false;
  const VoiceSheetResult.manual()
      : text = null,
        manual = true;

  final String? text;
  final bool manual;
}

/// Feuille « Je vous écoute… » : ondes sonores animées, texte reconnu en
/// direct, et messages d'erreur avec repli vers la saisie manuelle.
Future<VoiceSheetResult?> showVoiceInputSheet(BuildContext context) => showModalBottomSheet<VoiceSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _VoiceSheet(),
    );

class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet();

  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> with SingleTickerProviderStateMixin {
  late final VoiceInput _voice = context.read<VoiceInput>();
  late final AnimationController _wave =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  String _text = '';
  double _level = 0;
  bool _listening = false;
  VoiceError? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _text = '';
      _error = null;
      _listening = true;
      _level = 0;
    });
    try {
      await _voice.start(
        onText: (text, isFinal) {
          if (!mounted) return;
          setState(() => _text = text);
          if (isFinal) _finish();
        },
        onLevel: (l) {
          if (mounted) setState(() => _level = l);
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _error = e;
              _listening = false;
            });
          }
        },
        onDone: _finish,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = VoiceError.unavailable;
          _listening = false;
        });
      }
    }
  }

  void _finish() {
    if (!mounted || !_listening) return;
    _listening = false;
    if (_text.trim().isEmpty) {
      setState(() => _error = VoiceError.noSpeech);
      return;
    }
    Navigator.pop(context, VoiceSheetResult.text(_text));
  }

  @override
  void dispose() {
    if (_listening) _voice.cancel();
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = _error;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: e != null ? _errorView(context, e) : _listeningView(theme),
      ),
    );
  }

  Widget _listeningView(ThemeData theme) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Je vous écoute…', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Par exemple : « ajoute lait, pain et 6 œufs »', style: theme.textTheme.bodySmall),
        const SizedBox(height: 20),
        SizedBox(
          height: 72,
          child: AnimatedBuilder(
            animation: _wave,
            builder: (_, _) => CustomPaint(
              size: const Size(220, 72),
              painter: _WavePainter(phase: _wave.value, level: _level, color: theme.colorScheme.primary),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _text.isEmpty ? '…' : _text,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, const VoiceSheetResult.manual()),
              child: const Text('Saisir à la main'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: () async {
                await _voice.stop();
                _finish();
              },
              icon: const Icon(Icons.stop),
              label: const Text('Terminer'),
            ),
          ),
        ]),
      ]);

  Widget _errorView(BuildContext context, VoiceError e) {
    final (icon, title, message) = switch (e) {
      VoiceError.permissionDenied => (
          Icons.mic_off,
          'Accès au micro refusé',
          'PanierMalin a besoin du micro pour comprendre les articles que vous dictez. '
              'Rien n\'est enregistré ni envoyé ailleurs que pour la reconnaissance.',
        ),
      VoiceError.permissionPermanentlyDenied => (
          Icons.mic_off,
          'Micro bloqué',
          'L\'accès au micro a été refusé définitivement. Autorisez-le dans les réglages du téléphone : '
              'Applications › PanierMalin › Autorisations › Micro.',
        ),
      VoiceError.noSpeech => (
          Icons.hearing_disabled,
          'Aucun son détecté',
          'Parlez près du téléphone, par exemple : « ajoute lait, pain et 6 œufs ».',
        ),
      VoiceError.offline => (
          Icons.cloud_off,
          'Reconnaissance indisponible hors ligne',
          'La reconnaissance vocale de ce téléphone a besoin d\'Internet (ou du pack de langue français '
              'hors ligne). Connectez-vous ou saisissez les articles à la main.',
        ),
      VoiceError.unavailable => (
          Icons.voice_over_off,
          'Reconnaissance vocale indisponible',
          'Ce téléphone ne propose pas de reconnaissance vocale. Saisissez les articles à la main.',
        ),
      VoiceError.other => (Icons.error_outline, 'L\'écoute a échoué', 'Réessayez ou saisissez les articles à la main.'),
    };
    final canRetry = e == VoiceError.permissionDenied || e == VoiceError.noSpeech || e == VoiceError.other || e == VoiceError.offline;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 48, color: Theme.of(context).colorScheme.error),
      const SizedBox(height: 8),
      Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(message, textAlign: TextAlign.center),
      const SizedBox(height: 20),
      if (e == VoiceError.permissionPermanentlyDenied)
        FilledButton.icon(
          onPressed: _voice.openSettings,
          icon: const Icon(Icons.settings),
          label: const Text('Ouvrir les réglages'),
        ),
      if (canRetry)
        FilledButton.icon(onPressed: _start, icon: const Icon(Icons.mic), label: const Text('Réessayer')),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: () => Navigator.pop(context, const VoiceSheetResult.manual()),
        icon: const Icon(Icons.keyboard),
        label: const Text('Saisir à la main'),
      ),
    ]);
  }
}

/// Ondes sonores : des barres dont la hauteur suit le niveau du micro, avec
/// une légère ondulation même dans le silence pour montrer que l'app écoute.
class _WavePainter extends CustomPainter {
  _WavePainter({required this.phase, required this.level, required this.color});
  final double phase;
  final double level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 15;
    final gap = size.width / bars;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = gap * 0.45;
    for (var i = 0; i < bars; i++) {
      final centre = 1 - ((i - (bars - 1) / 2).abs() / bars); // plus haut au centre
      final wobble = 0.5 + 0.5 * math.sin(2 * math.pi * (phase + i / bars * 1.5));
      final amp = (0.12 + 0.88 * level) * centre * (0.55 + 0.45 * wobble);
      final h = math.max(4.0, size.height * amp);
      final x = gap * (i + 0.5);
      canvas.drawLine(Offset(x, (size.height - h) / 2), Offset(x, (size.height + h) / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.phase != phase || old.level != level || old.color != color;
}
