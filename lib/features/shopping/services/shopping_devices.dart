import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';

import '../logic/budget_forecast.dart';
import '../logic/heartbeat.dart';
import '../logic/live_receipt_parser.dart';
import '../logic/live_scan_tracker.dart';
import '../logic/ocr_rows.dart';
import '../logic/shake_detector.dart';

/// Capteurs et stockage sécurisé de la gestion 5, derrière des interfaces
/// pour que les tests puissent les remplacer.

// ------------------------------------------------------------------ Vibreur

abstract interface class AlertVibrator {
  /// Vibration d'alerte : motif court au seuil, long quand le budget est
  /// atteint ou dépassé. Renvoie false si l'appareil n'a pas de vibreur.
  Future<bool> alert(BudgetLevel level);

  /// Battement de cœur « tou-toum » (motif et intensités). Renvoie false si
  /// l'appareil n'a pas de vibreur ou si le motif est vide (budget < 50 %).
  Future<bool> heartbeat(HeartbeatPattern pattern);
}

/// Motif de vibration (pause, vibration, pause, vibration… en ms).
List<int> vibrationPattern(BudgetLevel level) => switch (level) {
      BudgetLevel.exceeded => const [0, 700, 200, 700, 200, 700], // long
      BudgetLevel.threshold => const [0, 180, 120, 180], // court
      _ => const [0, 150],
    };

/// Durée totale du motif : l'animation à l'écran dure autant.
Duration vibrationDuration(BudgetLevel level) =>
    Duration(milliseconds: vibrationPattern(level).fold(0, (s, v) => s + v));

class DeviceAlertVibrator implements AlertVibrator {
  @override
  Future<bool> heartbeat(HeartbeatPattern pattern) async {
    if (pattern.isEmpty) return false;
    try {
      if (!await Vibration.hasVibrator()) return false;
      if (!await Vibration.hasCustomVibrationsSupport()) {
        await Vibration.vibrate(duration: pattern.total.inMilliseconds);
        return true;
      }
      // Intensités variables seulement si le vibreur sait les régler.
      await Vibration.vibrate(
        pattern: pattern.timings,
        intensities: await Vibration.hasAmplitudeControl() ? pattern.intensities : const [],
      );
      return true;
    } catch (e) {
      debugPrint('Vibreur indisponible : $e');
      return false;
    }
  }

  @override
  Future<bool> alert(BudgetLevel level) async {
    try {
      if (!await Vibration.hasVibrator()) return false; // tablette, émulateur sans vibreur…
      if (await Vibration.hasCustomVibrationsSupport()) {
        await Vibration.vibrate(pattern: vibrationPattern(level));
      } else {
        // Sans motifs personnalisés : une vibration simple de même durée.
        await Vibration.vibrate(duration: level == BudgetLevel.exceeded ? 1200 : 300);
      }
      return true;
    } catch (e) {
      debugPrint('Vibreur indisponible : $e');
      return false;
    }
  }
}

class SilentVibrator implements AlertVibrator {
  SilentVibrator({this.hasVibrator = true});
  final bool hasVibrator;
  final List<BudgetLevel> calls = [];
  final List<HeartLevel> heartbeats = [];

  @override
  Future<bool> heartbeat(HeartbeatPattern pattern) async {
    if (pattern.isEmpty) return false;
    heartbeats.add(pattern.level);
    return hasVibrator;
  }

  @override
  Future<bool> alert(BudgetLevel level) async {
    calls.add(level);
    return hasVibrator;
  }
}

// ------------------------------------------------- Notifications locales

/// Notification quand une alerte de budget arrive app en arrière-plan.
abstract interface class LocalNotifier {
  /// Demande l'autorisation d'afficher des notifications (Android 13+, iOS).
  Future<bool> requestPermission();

  Future<void> show({required int id, required String title, required String body});

  /// Notification programmée à [at] (heure locale). Renvoie false si
  /// impossible (permission refusée, plateforme non prise en charge).
  Future<bool> schedule({required int id, required String title, required String body, required DateTime at});
}

class DeviceLocalNotifier implements LocalNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;
  static bool _tzReady = false;

  @override
  Future<bool> schedule({required int id, required String title, required String body, required DateTime at}) async {
    if (!await requestPermission()) return false;
    try {
      if (!_tzReady) {
        tz_data.initializeTimeZones();
        _tzReady = true;
      }
      // Instant absolu (UTC) : pas besoin de connaître le fuseau du téléphone
      // pour un rappel ponctuel.
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'shopping_reminders',
            "Rappels d'achat",
            channelDescription: 'Meilleur moment pour acheter un produit (Courses et Budget).',
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        // Pas d'alarme exacte (permission spéciale) : un rappel « en début de mois » peut glisser de quelques minutes.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return true;
    } catch (e) {
      debugPrint('Rappel non programmé : $e');
      return false;
    }
  }

  static AndroidNotificationDetails _channel(String body) => AndroidNotificationDetails(
        'budget_alerts',
        'Alertes de budget',
        channelDescription: 'Seuil d\'alerte franchi ou budget dépassé (Courses et Budget).',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        styleInformation: BigTextStyleInformation(body),
      );

  Future<bool> _init() => _ready ??= () async {
        try {
          return await _plugin.initialize(
                settings: const InitializationSettings(
                  android: AndroidInitializationSettings('@mipmap/ic_launcher'),
                  iOS: DarwinInitializationSettings(
                    requestAlertPermission: false,
                    requestBadgePermission: false,
                    requestSoundPermission: false,
                  ),
                ),
              ) ??
              false;
        } catch (e) {
          debugPrint('Notifications indisponibles : $e');
          return false;
        }
      }();

  @override
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    try {
      if (Platform.isAndroid) {
        return await _plugin
                .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
                ?.requestNotificationsPermission() ??
            false;
      }
      if (Platform.isIOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, sound: true) ??
            false;
      }
    } catch (e) {
      debugPrint('Permission notifications : $e');
    }
    return false;
  }

  @override
  Future<void> show({required int id, required String title, required String body}) async {
    if (!await _init()) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: _channel(body),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('Notification non affichée : $e');
    }
  }
}

class MemoryNotifier implements LocalNotifier {
  final List<(String, String)> shown = [];
  final List<(String, DateTime)> scheduled = [];

  @override
  Future<bool> schedule({required int id, required String title, required String body, required DateTime at}) async {
    scheduled.add((body, at));
    return true;
  }

  int permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> show({required int id, required String title, required String body}) async => shown.add((title, body));
}

// --------------------------------------------- Accéléromètre : secousses

/// Source des secousses. Chaque écoute ouvre son propre abonnement au
/// capteur : l'écran l'annule dans `dispose()` (ou quand il est masqué),
/// ce qui coupe l'accéléromètre et économise la batterie.
abstract interface class ShakeSource {
  Stream<void> shakes();
}

class AccelerometerShakeSource implements ShakeSource {
  AccelerometerShakeSource({this.thresholdG = 2.7});
  final double thresholdG;

  @override
  Stream<void> shakes() {
    final detector = ShakeDetector(thresholdG: thresholdG);
    return accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
        .where((e) => detector.add(e.x, e.y, e.z, DateTime.now()))
        .map((_) {})
        // Téléphone sans accéléromètre : pas de secousse, pas d'erreur à l'écran.
        .handleError((Object e) => debugPrint('Accéléromètre indisponible : $e'));
  }
}

// ------------------------------------------------- Micro : ajout vocal

/// Pourquoi l'écoute a échoué, pour afficher le bon message.
enum VoiceError {
  /// Permission micro refusée (on peut la redemander).
  permissionDenied,

  /// Refusée définitivement : il faut passer par les réglages du téléphone.
  permissionPermanentlyDenied,

  /// Rien entendu (silence, délai dépassé, aucun mot reconnu).
  noSpeech,

  /// Reconnaissance en ligne impossible (pas de réseau, langue non installée).
  offline,

  /// Pas de reconnaissance vocale sur ce téléphone.
  unavailable,

  other,
}

abstract interface class VoiceInput {
  /// Demande la permission micro puis écoute en français. [onText] reçoit le
  /// texte reconnu en direct (isFinal = vrai pour le dernier), [onLevel] le
  /// niveau sonore (0 à 1) pour l'animation, [onDone] la fin de l'écoute.
  Future<void> start({
    required void Function(String text, bool isFinal) onText,
    required void Function(double level) onLevel,
    required void Function(VoiceError error) onError,
    required void Function() onDone,
  });

  Future<void> stop();
  Future<void> cancel();

  /// Ouvre les réglages de l'application (permission refusée définitivement).
  Future<bool> openSettings();
}

class DeviceVoiceInput implements VoiceInput {
  // Singleton du plugin, partagé avec le mode cuisine de la gestion 3 :
  // on réassigne les écouteurs à chaque écoute.
  final SpeechToText _stt = SpeechToText();
  String? _localeId;
  bool _gotWords = false;

  @override
  Future<void> start({
    required void Function(String text, bool isFinal) onText,
    required void Function(double level) onLevel,
    required void Function(VoiceError error) onError,
    required void Function() onDone,
  }) async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) status = await Permission.microphone.request();
    if (status.isPermanentlyDenied || status.isRestricted) return onError(VoiceError.permissionPermanentlyDenied);
    if (!status.isGranted) return onError(VoiceError.permissionDenied);

    var finished = false;
    void finish() {
      if (finished) return;
      finished = true;
      onDone();
    }

    void error(SpeechRecognitionError e) {
      if (finished) return;
      finished = true;
      onError(switch (e.errorMsg) {
        'error_no_match' || 'error_speech_timeout' => VoiceError.noSpeech,
        'error_network' || 'error_network_timeout' || 'error_server' || 'error_server_disconnected' ||
        'error_language_not_supported' || 'error_language_unavailable' =>
          VoiceError.offline,
        'error_permission' || 'error_insufficient_permissions' => VoiceError.permissionDenied,
        _ => VoiceError.other,
      });
    }

    bool available;
    try {
      available = await _stt.initialize(onError: error);
    } catch (_) {
      available = false;
    }
    if (!available) return onError(VoiceError.unavailable);
    _stt.errorListener = error;
    _stt.statusListener = (s) {
      if (s == SpeechToText.doneStatus) {
        if (!_gotWords) {
          if (!finished) {
            finished = true;
            onError(VoiceError.noSpeech);
          }
        } else {
          finish();
        }
      }
    };
    _localeId ??= (await _stt.locales())
            .where((l) => l.localeId.toLowerCase().replaceAll('-', '_') == 'fr_fr')
            .map((l) => l.localeId)
            .firstOrNull ??
        (await _stt.locales()).where((l) => l.localeId.toLowerCase().startsWith('fr')).map((l) => l.localeId).firstOrNull ??
        'fr_FR';
    _gotWords = false;
    await _stt.listen(
      onResult: (r) {
        if (r.recognizedWords.isNotEmpty) _gotWords = true;
        onText(r.recognizedWords, r.finalResult);
        if (r.finalResult) finish();
      },
      // Le niveau est en dB (≈ -2 à 10 sur Android) : ramené entre 0 et 1.
      onSoundLevelChange: (db) => onLevel(((db + 2) / 12).clamp(0, 1).toDouble()),
      listenOptions: SpeechListenOptions(
        localeId: _localeId,
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  @override
  Future<void> stop() => _stt.stop();

  @override
  Future<void> cancel() => _stt.cancel();

  @override
  Future<bool> openSettings() => openAppSettings();
}

// ---------------------------------------------------- Caméra + lecture OCR

enum PhotoSource { camera, gallery }

abstract interface class ReceiptReader {
  /// Prend (ou choisit) une photo de ticket et la copie dans le dossier de
  /// l'app. Renvoie son chemin, ou null si l'utilisateur annule.
  Future<String?> capture(PhotoSource source);

  /// Reconnaît le texte du ticket, ligne par ligne.
  Future<String> readText(String photoPath);
}

class MlKitReceiptReader implements ReceiptReader {
  final _picker = ImagePicker();

  @override
  Future<String?> capture(PhotoSource source) async {
    if (source == PhotoSource.camera) {
      // La permission CAMERA est déclarée (scan en direct) : Android exige
      // alors qu'elle soit accordée avant d'ouvrir l'appareil photo.
      final status = await Permission.camera.request();
      if (!status.isGranted) throw const LiveCameraException(LiveCameraError.permissionDenied);
    }
    final file = await _picker.pickImage(
      source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2400,
      imageQuality: 90,
    );
    if (file == null) return null;
    return keepReceiptPhoto(file.path);
  }

  @override
  Future<String> readText(String photoPath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(photoPath));
      final fragments = [
        for (final block in result.blocks)
          for (final line in block.lines)
            OcrFragment(
              line.text,
              left: line.boundingBox.left,
              top: line.boundingBox.top,
              right: line.boundingBox.right,
              bottom: line.boundingBox.bottom,
            ),
      ];
      return rowsFromFragments(fragments).join('\n');
    } finally {
      await recognizer.close();
    }
  }
}

/// Copie la photo d'un ticket dans le dossier de l'app (receipt_photos).
Future<String> keepReceiptPhoto(String path) async {
  final dir = Directory('${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}receipt_photos');
  await dir.create(recursive: true);
  final dest = '${dir.path}${Platform.pathSeparator}ticket_${DateTime.now().millisecondsSinceEpoch}.jpg';
  await File(path).copy(dest);
  return dest;
}

// ------------------------------------- Caméra en direct : scan du ticket

enum LiveCameraError {
  /// Permission caméra refusée (on peut la redemander).
  permissionDenied,

  /// Refusée définitivement : réglages du téléphone.
  permissionPermanentlyDenied,

  /// Pas de caméra sur l'appareil.
  noCamera,

  /// La caméra n'a pas pu démarrer (occupée par une autre app…).
  failed,
}

class LiveCameraException implements Exception {
  const LiveCameraException(this.error, [this.detail]);
  final LiveCameraError error;
  final String? detail;

  @override
  String toString() => switch (error) {
        LiveCameraError.permissionDenied || LiveCameraError.permissionPermanentlyDenied => 'Accès à la caméra refusé.',
        LiveCameraError.noCamera => 'Aucune caméra sur cet appareil.',
        LiveCameraError.failed => 'La caméra n\'a pas pu démarrer${detail == null ? '' : ' ($detail)'}.',
      };
}

/// Une image du flux lue par la reconnaissance de texte.
class LiveFrame {
  const LiveFrame({required this.rows, this.brightness});

  /// Rangées de texte, positions relatives (0–1) à l'image droite.
  final List<LiveOcrRow> rows;

  /// Luminosité moyenne 0–1 (null si inconnue).
  final double? brightness;
}

/// Caméra du scan en direct : aperçu, flux d'images lues (~3 par seconde),
/// lampe, photo finale. Une instance par écran, fermée dans `dispose()`.
abstract interface class LiveReceiptCamera {
  /// Demande la permission puis ouvre la caméra arrière.
  /// Lève [LiveCameraException].
  Future<void> open();

  /// Aperçu plein écran (rogné pour remplir) avec [overlay] dessiné par-dessus
  /// dans les coordonnées de l'image.
  Widget buildPreview(Widget overlay);

  Stream<LiveFrame> frames();

  Future<void> setTorch(bool on);

  /// Arrête le flux et prend la photo du ticket (copiée dans l'app).
  Future<String?> takePhoto();

  Future<bool> openSettings();

  Future<void> close();
}

typedef LiveCameraFactory = LiveReceiptCamera Function();

class DeviceLiveReceiptCamera implements LiveReceiptCamera {
  DeviceLiveReceiptCamera({Duration minInterval = const Duration(milliseconds: 333)})
      : _gate = FrameGate(minInterval: minInterval);

  final FrameGate _gate;
  CameraController? _controller;
  CameraDescription? _camera;
  TextRecognizer? _recognizer;
  StreamController<LiveFrame>? _frames;
  bool _streaming = false;
  bool _closed = false;

  @override
  Future<void> open() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) status = await Permission.camera.request();
    if (status.isPermanentlyDenied || status.isRestricted) {
      throw const LiveCameraException(LiveCameraError.permissionPermanentlyDenied);
    }
    if (!status.isGranted) throw const LiveCameraException(LiveCameraError.permissionDenied);

    final List<CameraDescription> cams;
    try {
      cams = await availableCameras();
    } on CameraException catch (e) {
      throw LiveCameraException(LiveCameraError.failed, e.description);
    }
    if (cams.isEmpty) throw const LiveCameraException(LiveCameraError.noCamera);
    final cam = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
    final c = CameraController(
      cam,
      ResolutionPreset.high, // 720p : assez net pour les petits caractères d'un ticket
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    try {
      await c.initialize();
    } on CameraException catch (e) {
      await c.dispose();
      if (e.code.contains('AccessDenied') || e.code.toLowerCase().contains('permission')) {
        throw const LiveCameraException(LiveCameraError.permissionDenied);
      }
      throw LiveCameraException(LiveCameraError.failed, e.description);
    }
    try {
      await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await c.setFlashMode(FlashMode.off);
    } catch (_) {}
    _camera = cam;
    _controller = c;
    _closed = false;
    _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  }

  @override
  Widget buildPreview(Widget overlay) {
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.previewSize == null) {
      return const ColoredBox(color: Color(0xFF000000));
    }
    final size = c.value.previewSize!; // en paysage (largeur > hauteur)
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(width: size.height, height: size.width, child: CameraPreview(c, child: overlay)),
      ),
    );
  }

  @override
  Stream<LiveFrame> frames() {
    final out = StreamController<LiveFrame>();
    _frames = out;
    out.onListen = () async {
      final c = _controller;
      if (c == null || _streaming) return;
      try {
        await c.startImageStream(_onImage);
        _streaming = true;
      } catch (e) {
        out.addError(LiveCameraException(LiveCameraError.failed, '$e'));
      }
    };
    out.onCancel = _stopStream;
    return out.stream;
  }

  Future<void> _stopStream() async {
    if (!_streaming) return;
    _streaming = false;
    try {
      await _controller?.stopImageStream();
    } catch (_) {}
  }

  Future<void> _onImage(CameraImage image) async {
    // ~3 images par seconde, jamais deux lectures en même temps.
    if (_closed || !_gate.tryStart(DateTime.now())) return;
    try {
      final rotation = _rotation();
      final input = _inputImage(image, rotation);
      if (input == null || _recognizer == null) return;
      final brightness = _brightness(image);
      final result = await _recognizer!.processImage(input);
      if (_closed) return;
      // Image « droite » : largeur et hauteur échangées si le capteur est tourné.
      final turned = Platform.isAndroid &&
          (rotation == InputImageRotation.rotation90deg || rotation == InputImageRotation.rotation270deg);
      final w = (turned ? image.height : image.width).toDouble();
      final h = (turned ? image.width : image.height).toDouble();
      final rows = groupRows([
        for (final block in result.blocks)
          for (final line in block.lines)
            OcrFragment(
              line.text,
              left: line.boundingBox.left,
              top: line.boundingBox.top,
              right: line.boundingBox.right,
              bottom: line.boundingBox.bottom,
              confidence: line.confidence,
            ),
      ]);
      _frames?.add(LiveFrame(
        brightness: brightness,
        rows: [
          for (final r in rows)
            LiveOcrRow(r.text, box: Rect.fromLTRB(r.left / w, r.top / h, r.right / w, r.bottom / h), confidence: r.confidence),
        ],
      ));
    } catch (e) {
      debugPrint('Lecture du flux impossible : $e');
    } finally {
      _gate.done();
      if (_closed) await _closeRecognizer();
    }
  }

  InputImageRotation _rotation() {
    final sensor = _camera?.sensorOrientation ?? 90;
    // Écran bloqué en portrait : la compensation vaut l'orientation du capteur.
    return InputImageRotationValue.fromRawValue(sensor) ?? InputImageRotation.rotation90deg;
  }

  InputImage? _inputImage(CameraImage image, InputImageRotation rotation) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null || image.planes.length != 1) return null; // nv21 / bgra8888 : un seul plan
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  double? _brightness(CameraImage image) {
    final bytes = image.planes.first.bytes;
    if (Platform.isAndroid) {
      // NV21 : les largeur × hauteur premiers octets sont la luminance.
      final y = image.width * image.height;
      return meanLuma(bytes.length > y ? Uint8List.sublistView(bytes, 0, y) : bytes);
    }
    // BGRA : la composante verte approche la luminance.
    var sum = 0;
    var n = 0;
    for (var i = 1; i < bytes.length; i += 4 * 23) {
      sum += bytes[i];
      n++;
    }
    return n == 0 ? null : sum / n / 255;
  }

  @override
  Future<void> setTorch(bool on) async {
    try {
      await _controller?.setFlashMode(on ? FlashMode.torch : FlashMode.off);
    } catch (e) {
      debugPrint('Lampe indisponible : $e');
    }
  }

  @override
  Future<String?> takePhoto() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return null;
    await _stopStream();
    try {
      await c.setFlashMode(FlashMode.off);
    } catch (_) {}
    final file = await c.takePicture();
    return keepReceiptPhoto(file.path);
  }

  @override
  Future<bool> openSettings() => openAppSettings();

  Future<void> _closeRecognizer() async {
    final r = _recognizer;
    _recognizer = null;
    await r?.close();
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _stopStream();
    final c = _controller;
    _controller = null;
    await c?.dispose();
    if (!_gate.busy) await _closeRecognizer();
    await _frames?.close();
    _frames = null;
  }
}

// ------------------------------------------------------- Stockage sécurisé

/// Jeton Open Prices, stocké avec flutter_secure_storage (cahier des charges
/// §11 : clés d'API dans le stockage sécurisé).
abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String? token);
}

class SecureTokenStore implements TokenStore {
  static const _key = 'open_prices_token';
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String? token) =>
      token == null ? _storage.delete(key: _key) : _storage.write(key: _key, value: token);
}

class MemoryTokenStore implements TokenStore {
  String? token;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String? t) async => token = t;
}
