import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
//  FOTOCABINA PRO  (versión final)
//
//  Dependencias (pubspec.yaml): camera, network_info_plus, pdf, printing,
//  qr_flutter y shared_preferences  ->  flutter pub add shared_preferences
//
//  Info.plist (iOS):
//    NSCameraUsageDescription
//    NSLocalNetworkUsageDescription
//
//  Funciones:
//  - Tira clásica (2 tiras de 2-4 fotos en papel 4x6) o cuadrícula 2x2
//  - Efectos, marcos, adornos (emojis) y color de fondo en la imagen final
//  - Cuenta atrás animada, flash, háptica y sonido
//  - Modo automático (secuencia) o manual (una pulsación por foto)
//  - Repetir una foto concreta o toda la sesión
//  - Impresión directa AirPrint o con diálogo; impresión automática opcional
//  - QR con página web local (tira + fotos originales)
//  - Cierre por inactividad y borrado de fotos al terminar
//  - Panel de operador con PIN, ajustes guardados y estadísticas
// ============================================================================

const List<String> kEffectNames = [
  'Natural',
  'Blanco y negro',
  'Cálido',
  'Frío',
  'Sepia',
  'Alto contraste',
];

const List<String> kFrameNames = [
  'Sin marco',
  'Color personalizado',
  'Blanco',
  'Rosa',
  'Azul',
  'Neón',
];

const List<String> kLayoutNames = [
  'Tira clásica (2 tiras iguales)',
  'Cuadrícula 2 x 2',
];

const List<String> kStickerNames = [
  'Sin adornos',
  'Fiesta',
  'Corazones',
  'Estrellas',
  'Boda',
];

const List<List<String>> kStickerSets = <List<String>>[
  <String>[],
  <String>['🎉', '🎈', '🥳', '✨'],
  <String>['❤️', '💖', '💕', '😍'],
  <String>['⭐', '✨', '🌟', '💫'],
  <String>['💍', '🥂', '💐', '🤍'],
];

const List<String> kSheetNames = [
  'Blanco',
  'Negro',
  'Dorado',
  'Rosa',
  'Azul noche',
];

const List<Color> kSheetColors = <Color>[
  Color(0xFFFFFFFF),
  Color(0xFF111116),
  Color(0xFFE7B66A),
  Color(0xFFFFC2DC),
  Color(0xFF14213D),
];

const List<int> kCountdownOptions = [3, 5, 10];
const List<int> kIdleOptions = [60, 90, 120, 180];

/// Matrices de color (4x5). El índice coincide con [kEffectNames].
const List<List<double>> kEffectMatrices = <List<double>>[
  // Natural
  <double>[
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ],
  // Blanco y negro
  <double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ],
  // Cálido
  <double>[
    1.08, 0, 0, 0, 8,
    0, 1.00, 0, 0, 2,
    0, 0, 0.86, 0, 0,
    0, 0, 0, 1, 0,
  ],
  // Frío
  <double>[
    0.90, 0, 0, 0, 0,
    0, 1.00, 0, 0, 0,
    0, 0, 1.12, 0, 8,
    0, 0, 0, 1, 0,
  ],
  // Sepia
  <double>[
    0.393, 0.769, 0.189, 0, 0,
    0.349, 0.686, 0.168, 0, 0,
    0.272, 0.534, 0.131, 0, 0,
    0, 0, 0, 1, 0,
  ],
  // Alto contraste
  <double>[
    1.25, 0, 0, 0, -20,
    0, 1.25, 0, 0, -20,
    0, 0, 1.25, 0, -20,
    0, 0, 0, 1, 0,
  ],
];

enum BoothLayout { strip, grid }

/// Configuración del evento (la edita el operador y se guarda en el iPad).
class BoothSettings {
  BoothSettings({
    this.eventName = 'Fotocabina Pro',
    this.welcomeText = 'Momentos que merecen recordarse.',
    this.footer = 'Un recuerdo para toda la vida',
    this.effect = 0,
    this.frame = 1,
    this.frameColor = const Color(0xFFE7B66A),
    this.sticker = 0,
    this.sheetBg = 0,
    this.layout = BoothLayout.strip,
    this.photoCount = 4,
    this.countdown = 3,
    this.autoSequence = true,
    this.mirrorPhotos = false,
    this.shutterSound = true,
    this.idleSeconds = 90,
    this.maxCopies = 3,
    this.printEnabled = true,
    this.shareEnabled = true,
    this.autoPrint = false,
    this.pin = '1234',
    this.printerUrl,
    this.printerName,
  });

  String eventName;
  String welcomeText;
  String footer;
  int effect;
  int frame;
  Color frameColor;
  int sticker;
  int sheetBg;
  BoothLayout layout;
  int photoCount;
  int countdown;
  bool autoSequence;
  bool mirrorPhotos;
  bool shutterSound;
  int idleSeconds;
  int maxCopies;
  bool printEnabled;
  bool shareEnabled;
  bool autoPrint;
  String pin;
  String? printerUrl;
  String? printerName;

  BoothSettings copy() => BoothSettings(
        eventName: eventName,
        welcomeText: welcomeText,
        footer: footer,
        effect: effect,
        frame: frame,
        frameColor: frameColor,
        sticker: sticker,
        sheetBg: sheetBg,
        layout: layout,
        photoCount: photoCount,
        countdown: countdown,
        autoSequence: autoSequence,
        mirrorPhotos: mirrorPhotos,
        shutterSound: shutterSound,
        idleSeconds: idleSeconds,
        maxCopies: maxCopies,
        printEnabled: printEnabled,
        shareEnabled: shareEnabled,
        autoPrint: autoPrint,
        pin: pin,
        printerUrl: printerUrl,
        printerName: printerName,
      );

  /// Restaura los valores por defecto conservando el PIN.
  void restoreDefaults() {
    final d = BoothSettings();
    eventName = d.eventName;
    welcomeText = d.welcomeText;
    footer = d.footer;
    effect = d.effect;
    frame = d.frame;
    frameColor = d.frameColor;
    sticker = d.sticker;
    sheetBg = d.sheetBg;
    layout = d.layout;
    photoCount = d.photoCount;
    countdown = d.countdown;
    autoSequence = d.autoSequence;
    mirrorPhotos = d.mirrorPhotos;
    shutterSound = d.shutterSound;
    idleSeconds = d.idleSeconds;
    maxCopies = d.maxCopies;
    printEnabled = d.printEnabled;
    shareEnabled = d.shareEnabled;
    autoPrint = d.autoPrint;
    printerUrl = null;
    printerName = null;
  }

  factory BoothSettings.load(SharedPreferences p) {
    final d = BoothSettings();
    int pick(String key, int def, int length) {
      final v = p.getInt(key) ?? def;
      return (v < 0 || v >= length) ? def : v;
    }

    int oneOf(String key, int def, List<int> allowed) {
      final v = p.getInt(key) ?? def;
      return allowed.contains(v) ? v : def;
    }

    return BoothSettings(
      eventName: p.getString('eventName') ?? d.eventName,
      welcomeText: p.getString('welcomeText') ?? d.welcomeText,
      footer: p.getString('footer') ?? d.footer,
      effect: pick('effect', d.effect, kEffectNames.length),
      frame: pick('frame', d.frame, kFrameNames.length),
      frameColor: Color(p.getInt('frameColor') ?? d.frameColor.toARGB32()),
      sticker: pick('sticker', d.sticker, kStickerNames.length),
      sheetBg: pick('sheetBg', d.sheetBg, kSheetNames.length),
      layout: BoothLayout.values[pick('layout', 0, BoothLayout.values.length)],
      photoCount: (p.getInt('photoCount') ?? d.photoCount).clamp(2, 4).toInt(),
      countdown: oneOf('countdown', d.countdown, kCountdownOptions),
      autoSequence: p.getBool('autoSequence') ?? d.autoSequence,
      mirrorPhotos: p.getBool('mirrorPhotos') ?? d.mirrorPhotos,
      shutterSound: p.getBool('shutterSound') ?? d.shutterSound,
      idleSeconds: oneOf('idleSeconds', d.idleSeconds, kIdleOptions),
      maxCopies: (p.getInt('maxCopies') ?? d.maxCopies).clamp(1, 5).toInt(),
      printEnabled: p.getBool('printEnabled') ?? d.printEnabled,
      shareEnabled: p.getBool('shareEnabled') ?? d.shareEnabled,
      autoPrint: p.getBool('autoPrint') ?? d.autoPrint,
      pin: p.getString('pin') ?? d.pin,
      printerUrl: p.getString('printerUrl'),
      printerName: p.getString('printerName'),
    );
  }

  Future<void> save(SharedPreferences p) async {
    await p.setString('eventName', eventName);
    await p.setString('welcomeText', welcomeText);
    await p.setString('footer', footer);
    await p.setInt('effect', effect);
    await p.setInt('frame', frame);
    await p.setInt('frameColor', frameColor.toARGB32());
    await p.setInt('sticker', sticker);
    await p.setInt('sheetBg', sheetBg);
    await p.setInt('layout', layout.index);
    await p.setInt('photoCount', photoCount);
    await p.setInt('countdown', countdown);
    await p.setBool('autoSequence', autoSequence);
    await p.setBool('mirrorPhotos', mirrorPhotos);
    await p.setBool('shutterSound', shutterSound);
    await p.setInt('idleSeconds', idleSeconds);
    await p.setInt('maxCopies', maxCopies);
    await p.setBool('printEnabled', printEnabled);
    await p.setBool('shareEnabled', shareEnabled);
    await p.setBool('autoPrint', autoPrint);
    await p.setString('pin', pin);
    if (printerUrl == null) {
      await p.remove('printerUrl');
      await p.remove('printerName');
    } else {
      await p.setString('printerUrl', printerUrl!);
      if (printerName == null) {
        await p.remove('printerName');
      } else {
        await p.setString('printerName', printerName!);
      }
    }
  }

  /// Color del marco o null si no hay marco.
  Color? get frameResolvedColor {
    switch (frame) {
      case 1:
        return frameColor;
      case 2:
        return Colors.white;
      case 3:
        return const Color(0xFFFF6FAE);
      case 4:
        return const Color(0xFF66BFFF);
      case 5:
        return const Color(0xFF39FFB6);
      default:
        return null;
    }
  }

  bool get neon => frame == 5;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  List<CameraDescription> cameras = [];
  try {
    cameras = await availableCameras();
  } catch (_) {
    // La aplicación también puede abrirse sin cámara disponible.
  }
  final prefs = await SharedPreferences.getInstance();
  runApp(FotocabinaPro(cameras: cameras, prefs: prefs));
}

class FotocabinaPro extends StatelessWidget {
  const FotocabinaPro({super.key, required this.cameras, required this.prefs});
  final List<CameraDescription> cameras;
  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fotocabina Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101014),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE7B66A),
          brightness: Brightness.dark,
        ),
      ),
      home: BoothScreen(cameras: cameras, prefs: prefs),
    );
  }
}

enum BoothState { welcome, camera, preview }

class BoothScreen extends StatefulWidget {
  const BoothScreen({super.key, required this.cameras, required this.prefs});
  final List<CameraDescription> cameras;
  final SharedPreferences prefs;

  @override
  State<BoothScreen> createState() => _BoothScreenState();
}

class _BoothScreenState extends State<BoothScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const Color gold = Color(0xFFE7B66A);
  static const Color panel = Color(0xFF1C1C24);
  static const PdfPageFormat _sheetFormat = PdfPageFormat(
    4 * PdfPageFormat.inch,
    6 * PdfPageFormat.inch,
  );

  // --- Estado de cámara y sesión ------------------------------------------
  CameraController? _camera;
  CameraDescription? _cameraDescription;
  final List<XFile> _photos = [];
  Uint8List? _composite; // Hoja final con efecto, marco y adornos incluidos.
  BoothState _state = BoothState.welcome;
  bool _busy = false;
  bool _countingDown = false;
  bool _flash = false;
  bool _resumeCamera = false;
  bool _mirrorPhotos = false;
  int _countdown = 0;
  int _copies = 1;
  int? _retakeIndex;
  int _session = DateTime.now().microsecondsSinceEpoch;
  int _sessionsCount = 0;
  int _printsCount = 0;
  int _idleLeft = 90;
  Timer? _timer;
  Timer? _idleTimer;

  // --- Compartir por QR ------------------------------------------------------
  HttpServer? _photoServer;
  String? _shareUrl;

  // --- Configuración -----------------------------------------------------------
  late BoothSettings _s;

  // --- Animación del botón de inicio -------------------------------------------
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final Animation<double> _pulseScale = Tween<double>(
    begin: 1,
    end: 1.05,
  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  int get _total => _s.layout == BoothLayout.grid ? 4 : _s.photoCount;

  Printer? get _printer => _s.printerUrl == null
      ? null
      : Printer(url: _s.printerUrl!, name: _s.printerName);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _s = BoothSettings.load(widget.prefs);
    _sessionsCount = widget.prefs.getInt('sessions') ?? 0;
    _printsCount = widget.prefs.getInt('prints') ?? 0;
    _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    _timer?.cancel();
    _idleTimer?.cancel();
    _photoServer?.close(force: true);
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _saveStats() async {
    await widget.prefs.setInt('sessions', _sessionsCount);
    await widget.prefs.setInt('prints', _printsCount);
  }

  // Libera la cámara si la app pasa a segundo plano y la recupera al volver.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_state == BoothState.camera && _camera != null) {
        _timer?.cancel();
        _countingDown = false;
        _resumeCamera = true;
        _releaseCamera();
      }
    } else if (state == AppLifecycleState.resumed && _resumeCamera) {
      _resumeCamera = false;
      _openCamera().then((_) {
        if (!mounted) return;
        setState(() {});
        if (_s.autoSequence || _retakeIndex != null) _startCountdown();
      }).catchError((Object error) {
        _message('No se pudo recuperar la cámara: $error');
      });
    }
  }

  // ==========================================================================
  //  CÁMARA
  // ==========================================================================

  Future<void> _releaseCamera() async {
    final old = _camera;
    if (old == null) return;
    if (mounted) {
      setState(() => _camera = null);
      // Deja que el árbol de widgets suelte el controlador antes de liberarlo.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    } else {
      _camera = null;
    }
    await old.dispose();
  }

  Future<void> _openCamera({CameraDescription? description}) async {
    await _releaseCamera();
    final desc = description ??
        widget.cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => widget.cameras.first,
        );
    final controller = CameraController(
      desc,
      ResolutionPreset.veryHigh,
      enableAudio: false,
    );
    await controller.initialize();
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}
    if (!mounted) {
      await controller.dispose();
      return;
    }
    _camera = controller;
    _cameraDescription = desc;
  }

  Future<void> _startSession() async {
    if (_busy) return;
    if (widget.cameras.isEmpty) {
      _message('No se encontró una cámara disponible.');
      return;
    }
    setState(() => _busy = true);
    var ok = false;
    try {
      _idleTimer?.cancel();
      await _stopPhotoServer();
      await _deletePhotos();
      await _openCamera();
      if (!mounted) return;
      _composite = null;
      _retakeIndex = null;
      _copies = 1;
      _session = DateTime.now().microsecondsSinceEpoch;
      _sessionsCount++;
      _saveStats();
      setState(() => _state = BoothState.camera);
      ok = true;
    } on CameraException catch (error) {
      if (error.code.startsWith('CameraAccess')) {
        _message(
          'Permiso de cámara denegado. Actívalo en Ajustes > Fotocabina Pro.',
        );
      } else {
        _message('No se pudo iniciar la cámara: ${error.description ?? error.code}');
      }
    } catch (error) {
      _message('No se pudo iniciar la cámara: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // El contador se lanza cuando _busy ya es false.
    if (ok && mounted && _s.autoSequence) _startCountdown();
  }

  Future<void> _switchCamera() async {
    if (_busy || _countingDown || widget.cameras.length < 2) return;
    final current = _cameraDescription;
    final next = widget.cameras.firstWhere(
      (item) => item.name != current?.name,
      orElse: () => widget.cameras.first,
    );
    setState(() => _busy = true);
    try {
      await _openCamera(description: next);
      _message(next.lensDirection == CameraLensDirection.front
          ? 'Cámara frontal activada.'
          : 'Cámara trasera activada.');
    } catch (error) {
      _message('No se pudo cambiar la cámara: $error');
      if (current != null) {
        try {
          await _openCamera(description: current);
        } catch (_) {}
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCountdown() {
    if (_busy || _countingDown || _camera == null) return;
    _timer?.cancel();
    setState(() {
      _countdown = _s.countdown;
      _countingDown = true;
    });
    HapticFeedback.selectionClick();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown > 1) {
        setState(() => _countdown--);
        HapticFeedback.selectionClick();
      } else {
        timer.cancel();
        setState(() {
          _countdown = 0;
          _countingDown = false;
        });
        _takePhoto();
      }
    });
  }

  void _triggerFlash() {
    if (!mounted) return;
    setState(() => _flash = true);
    Future<void>.delayed(const Duration(milliseconds: 90), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  Future<void> _takePhoto() async {
    final camera = _camera;
    if (camera == null ||
        !camera.value.isInitialized ||
        camera.value.isTakingPicture ||
        _busy) {
      return;
    }
    setState(() => _busy = true);
    var done = false;
    var next = false;
    try {
      final photo = await camera.takePicture();
      if (_s.shutterSound) SystemSound.play(SystemSoundType.click);
      HapticFeedback.mediumImpact();
      _triggerFlash();
      if (!mounted) return;
      _mirrorPhotos = _s.mirrorPhotos &&
          camera.description.lensDirection == CameraLensDirection.front;

      final retake = _retakeIndex;
      if (retake != null && retake < _photos.length) {
        final old = _photos[retake];
        _photos[retake] = photo;
        _retakeIndex = null;
        _deleteFile(old.path);
        done = true;
      } else {
        _photos.add(photo);
        done = _photos.length >= _total;
        next = !done;
      }
      setState(() {});
    } catch (error) {
      _message('Error al tomar la foto: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (done) {
          await _showResults();
        } else if (next && _s.autoSequence && _state == BoothState.camera) {
          await Future<void>.delayed(const Duration(milliseconds: 900));
          if (mounted && _state == BoothState.camera) _startCountdown();
        }
      }
    }
  }

  // ==========================================================================
  //  RESULTADOS
  // ==========================================================================

  Future<void> _showResults() async {
    await _releaseCamera();
    if (!mounted) return;
    setState(() {
      _state = BoothState.preview;
      _composite = null;
    });
    _startIdleTimer();
    try {
      final bytes = await _renderComposite();
      if (!mounted) return;
      setState(() => _composite = bytes);
    } catch (error) {
      _message('No se pudo componer la imagen final: $error');
    }
    await _startPhotoServer();
    if (mounted &&
        _s.autoPrint &&
        _s.printEnabled &&
        _printer != null &&
        _composite != null) {
      _copies = 1;
      await _printPhotos(auto: true);
    }
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    _idleLeft = _s.idleSeconds;
    _idleTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_busy) return; // No cerrar mientras se imprime o se repite una foto.
      if (_idleLeft <= 1) {
        timer.cancel();
        _finishSession();
      } else {
        setState(() => _idleLeft--);
      }
    });
  }

  Future<void> _confirmRetake(int index) async {
    if (_busy) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Repetir la foto ${index + 1}?'),
        content: const Text('La foto actual se sustituirá por una nueva.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('NO'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('REPETIR'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) _retakePhoto(index);
  }

  Future<void> _retakePhoto(int index) async {
    if (_busy) return;
    setState(() => _busy = true);
    var ok = false;
    try {
      _idleTimer?.cancel();
      await _stopPhotoServer();
      await _openCamera();
      if (!mounted) return;
      _retakeIndex = index;
      setState(() => _state = BoothState.camera);
      ok = true;
    } catch (error) {
      _message('No se pudo abrir la cámara: $error');
      if (mounted) {
        _startIdleTimer();
        await _startPhotoServer();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (ok && mounted) _startCountdown();
  }

  Future<void> _finishSession() async {
    _timer?.cancel();
    _idleTimer?.cancel();
    _countingDown = false;
    await _stopPhotoServer();
    await _releaseCamera();
    await _deletePhotos();
    if (!mounted) return;
    setState(() {
      _composite = null;
      _retakeIndex = null;
      _countdown = 0;
      _busy = false;
      _session = DateTime.now().microsecondsSinceEpoch;
      _state = BoothState.welcome;
    });
  }

  Future<void> _deleteFile(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  Future<void> _deletePhotos() async {
    for (final photo in List<XFile>.of(_photos)) {
      await _deleteFile(photo.path);
    }
    _photos.clear();
  }

  // ==========================================================================
  //  COMPOSICIÓN DE LA IMAGEN FINAL
  // ==========================================================================

  Future<ui.Image> _decodeImage(String path) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1500);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _formatDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

  void _paintText(
    Canvas canvas,
    String text,
    Rect area,
    double fontSize,
    Color color, {
    FontWeight weight = FontWeight.w400,
    double letterSpacing = 0,
  }) {
    if (text.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          color: color,
          letterSpacing: letterSpacing,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: area.width);
    painter.paint(
      canvas,
      Offset(
        area.left + (area.width - painter.width) / 2,
        area.top + (area.height - painter.height) / 2,
      ),
    );
  }

  void _paintEmoji(Canvas canvas, String emoji, Offset center, double size) {
    final painter = TextPainter(
      text: TextSpan(text: emoji, style: TextStyle(fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  void _paintPhoto(Canvas canvas, ui.Image image, Rect dst, int index) {
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    final scale = max(dst.width / iw, dst.height / ih);
    final sw = dst.width / scale;
    final sh = dst.height / scale;
    final src = Rect.fromLTWH((iw - sw) / 2, (ih - sh) / 2, sw, sh);

    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..colorFilter = ColorFilter.matrix(kEffectMatrices[_s.effect]);

    const radius = Radius.circular(14);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(dst, radius));
    if (_mirrorPhotos) {
      canvas.translate(dst.center.dx * 2, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawImageRect(image, src, dst, paint);
    canvas.restore();

    final color = _s.frameResolvedColor;
    if (color != null) {
      const thickness = 12.0;
      final frameRect = RRect.fromRectAndRadius(
        dst.deflate(thickness / 2),
        radius,
      );
      if (_s.neon) {
        canvas.drawRRect(
          frameRect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = thickness * 2
            ..color = color.withValues(alpha: 0.55)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
        );
      }
      canvas.drawRRect(
        frameRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness
          ..color = color,
      );
    }

    if (_s.sticker != 0) {
      final set = kStickerSets[_s.sticker];
      final size = min(dst.width, dst.height) * 0.24;
      _paintEmoji(
        canvas,
        set[index % set.length],
        Offset(dst.right - size * 0.45, dst.top + size * 0.45),
        size,
      );
      _paintEmoji(
        canvas,
        set[(index + 1) % set.length],
        Offset(dst.left + size * 0.45, dst.bottom - size * 0.45),
        size,
      );
    }
  }

  Future<Uint8List> _renderComposite() async {
    const double w = 1200; // 4 in a 300 ppp
    const double h = 1800; // 6 in a 300 ppp
    final images = <ui.Image>[];
    try {
      for (final photo in _photos) {
        images.add(await _decodeImage(photo.path));
      }
      if (images.isEmpty) throw StateError('No hay fotografías.');

      final background = kSheetColors[_s.sheetBg];
      final lightBg = background.computeLuminance() > 0.5;
      final textColor = lightBg ? const Color(0xFF202027) : Colors.white;
      final subColor = lightBg ? const Color(0xFF777780) : Colors.white70;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, w, h));
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, w, h),
        Paint()..color = background,
      );

      final title = _s.eventName.toUpperCase();
      final footer = _s.footer;
      final date = _formatDate(DateTime.now());

      if (_s.layout == BoothLayout.grid) {
        const double gap = 24;
        const double cellW = (w - 80 - gap) / 2;
        const double cellH = (1660 - 160 - gap) / 2;
        _paintText(
          canvas,
          title,
          const Rect.fromLTWH(40, 30, w - 80, 110),
          54,
          textColor,
          weight: FontWeight.w800,
          letterSpacing: 6,
        );
        for (var i = 0; i < 4; i++) {
          final col = i % 2;
          final row = i ~/ 2;
          _paintPhoto(
            canvas,
            images[i % images.length],
            Rect.fromLTWH(
              40 + col * (cellW + gap),
              160 + row * (cellH + gap),
              cellW,
              cellH,
            ),
            i,
          );
        }
        _paintText(
          canvas,
          footer,
          const Rect.fromLTWH(40, 1672, w - 80, 70),
          40,
          textColor,
          weight: FontWeight.w600,
        );
        _paintText(
          canvas,
          date,
          const Rect.fromLTWH(40, 1740, w - 80, 44),
          28,
          subColor,
        );
      } else {
        // Dos tiras idénticas: se cortan por la mitad después de imprimir.
        final n = _s.photoCount;
        const double gap = 20;
        const double areaTop = 120;
        const double areaHeight = 1540;
        final cellH = (areaHeight - (n - 1) * gap) / n;
        for (var s = 0; s < 2; s++) {
          final x0 = s * 600.0;
          _paintText(
            canvas,
            title,
            Rect.fromLTWH(x0 + 20, 20, 560, 90),
            38,
            textColor,
            weight: FontWeight.w800,
            letterSpacing: 4,
          );
          for (var i = 0; i < n; i++) {
            _paintPhoto(
              canvas,
              images[i % images.length],
              Rect.fromLTWH(x0 + 40, areaTop + i * (cellH + gap), 520, cellH),
              i,
            );
          }
          _paintText(
            canvas,
            footer,
            Rect.fromLTWH(x0 + 20, 1672, 560, 70),
            30,
            textColor,
            weight: FontWeight.w600,
          );
          _paintText(
            canvas,
            date,
            Rect.fromLTWH(x0 + 20, 1740, 560, 40),
            26,
            subColor,
          );
        }
        canvas.drawLine(
          const Offset(600, 0),
          const Offset(600, h),
          Paint()
            ..color = subColor.withValues(alpha: 0.5)
            ..strokeWidth = 2,
        );
      }

      final picture = recorder.endRecording();
      final output = await picture.toImage(w.toInt(), h.toInt());
      final data = await output.toByteData(format: ui.ImageByteFormat.png);
      output.dispose();
      picture.dispose();
      if (data == null) throw StateError('No se pudo codificar la imagen.');
      return data.buffer.asUint8List();
    } finally {
      for (final image in images) {
        image.dispose();
      }
    }
  }

  // ==========================================================================
  //  IMPRESIÓN
  // ==========================================================================

  Future<Uint8List> _createPrintPdf(Uint8List sheet) async {
    final document = pw.Document();
    final image = pw.MemoryImage(sheet);
    for (var copy = 0; copy < _copies; copy++) {
      document.addPage(
        pw.Page(
          pageFormat: _sheetFormat,
          margin: pw.EdgeInsets.zero,
          build: (context) => pw.Image(image, fit: pw.BoxFit.fill),
        ),
      );
    }
    return document.save();
  }

  Future<void> _printPhotos({bool auto = false}) async {
    final sheet = _composite;
    if (sheet == null || _busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _createPrintPdf(sheet);
      final name = 'Fotocabina_$_session';
      var printed = false;
      final printer = _printer;
      if (printer != null) {
        // Impresión directa AirPrint, sin diálogo.
        try {
          printed = await Printing.directPrintPdf(
            printer: printer,
            name: name,
            format: _sheetFormat,
            onLayout: (_) async => bytes,
          );
        } catch (_) {
          printed = false;
        }
      }
      if (!printed && !auto) {
        printed = await Printing.layoutPdf(
          name: name,
          format: _sheetFormat,
          onLayout: (_) async => bytes,
        );
      }
      if (printed) {
        _printsCount += _copies;
        _saveStats();
        _message('Impresión enviada.');
      } else if (auto) {
        _message('No se pudo imprimir automáticamente. Usa el botón IMPRIMIR.');
      }
    } catch (error) {
      _message('No se pudo imprimir: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ==========================================================================
  //  SERVIDOR LOCAL PARA EL QR
  // ==========================================================================

  String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  Future<void> _startPhotoServer() async {
    await _stopPhotoServer();
    if (_photos.isEmpty || !_s.shareEnabled) return;
    try {
      final wifiIp = await NetworkInfo().getWifiIP();
      if (wifiIp == null || wifiIp.isEmpty) {
        _message(
          'No se pudo detectar la IP Wi-Fi del iPad. '
          'Conéctalo a la red local del evento y vuelve a intentarlo.',
        );
        return;
      }
      final random = Random.secure();
      final token = List.generate(
        32,
        (_) => random.nextInt(16).toRadixString(16),
      ).join();
      final server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        0, // Puerto libre elegido por el sistema.
        shared: false,
      );
      _photoServer = server;
      _shareUrl = 'http://$wifiIp:${server.port}/s/$token';
      server.listen((request) => _handleRequest(request, token));
      if (!mounted) {
        await _stopPhotoServer();
        return;
      }
      setState(() {});
      _message(
        'QR listo. Conecta el teléfono a la misma red Wi-Fi y escanea el código.',
      );
    } catch (error) {
      await _stopPhotoServer();
      _message('No se pudo iniciar el servidor local: $error');
    }
  }

  Future<void> _handleRequest(HttpRequest request, String token) async {
    final response = request.response;
    try {
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.headers.set('X-Content-Type-Options', 'nosniff');
      response.headers.set('Referrer-Policy', 'no-referrer');

      final parts = request.uri.pathSegments;
      final download = request.uri.queryParameters['download'] == '1';

      if (request.method != 'GET') {
        response.statusCode = HttpStatus.methodNotAllowed;
        await response.close();
        return;
      }

      // Página principal
      if (parts.length == 2 && parts[0] == 's' && parts[1] == token) {
        response.headers.contentType = ContentType.html;
        final sheetUrl = '/sheet/$token';
        final html = StringBuffer('''
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>Tus fotos - ${_escapeHtml(_s.eventName)}</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;max-width:760px;
margin:0 auto;padding:20px;background:#f4f4f6;color:#202027}
h1{font-size:28px;margin-bottom:6px}h2{font-size:20px;margin-top:32px}
.photo{background:#fff;padding:14px;margin:18px 0;border-radius:14px;
box-shadow:0 2px 8px #0001}
img{display:block;max-width:100%;height:auto;margin:auto;border-radius:8px}
a{display:inline-block;background:#202027;color:#fff;padding:12px 16px;
margin-top:12px;border-radius:9px;text-decoration:none}
small{color:#555}
</style>
</head>
<body>
<h1>${_escapeHtml(_s.eventName)}</h1>
<p>Pulsa cada botón para guardar la imagen en tu teléfono. Si no se descarga automáticamente, mantén pulsada la imagen y elige guardar.</p>
''');
        if (_composite != null) {
          html.write('''
<section class="photo">
<img src="$sheetUrl" alt="Tira de fotos">
<a href="$sheetUrl?download=1" download>Descargar tira completa</a>
</section>
''');
        }
        html.write('<h2>Fotos individuales</h2>');
        for (var i = 0; i < _photos.length; i++) {
          final imageUrl = '/photo/$token/$i';
          html.write('''
<section class="photo">
<img src="$imageUrl" alt="Fotografía ${i + 1}">
<a href="$imageUrl?download=1" download>Descargar fotografía ${i + 1}</a>
</section>
''');
        }
        html.write(
          '<p><small>El acceso termina cuando finalice la sesión.</small></p>'
          '</body></html>',
        );
        response.write(html.toString());
        await response.close();
        return;
      }

      // Hoja final
      if (parts.length == 2 && parts[0] == 'sheet' && parts[1] == token) {
        final sheet = _composite;
        if (sheet == null) {
          response.statusCode = HttpStatus.notFound;
          await response.close();
          return;
        }
        response.headers.contentType = ContentType('image', 'png');
        response.contentLength = sheet.length;
        if (download) {
          response.headers.set(
            'Content-Disposition',
            'attachment; filename="fotocabina_tira.png"',
          );
        }
        response.add(sheet);
        await response.close();
        return;
      }

      // Foto original
      if (parts.length == 3 && parts[0] == 'photo' && parts[1] == token) {
        final index = int.tryParse(parts[2]);
        if (index == null || index < 0 || index >= _photos.length) {
          response.statusCode = HttpStatus.notFound;
          await response.close();
          return;
        }
        final file = File(_photos[index].path);
        if (!await file.exists()) {
          response.statusCode = HttpStatus.notFound;
          await response.close();
          return;
        }
        response.headers.contentType = ContentType('image', 'jpeg');
        if (download) {
          response.headers.set(
            'Content-Disposition',
            'attachment; filename="fotocabina_${index + 1}.jpg"',
          );
        }
        await response.addStream(file.openRead());
        await response.close();
        return;
      }

      response.statusCode = HttpStatus.notFound;
      await response.close();
    } catch (_) {
      try {
        response.statusCode = HttpStatus.internalServerError;
        await response.close();
      } catch (_) {
        // El navegador puede haberse desconectado.
      }
    }
  }

  Future<void> _stopPhotoServer() async {
    final server = _photoServer;
    _photoServer = null;
    _shareUrl = null;
    if (server != null) {
      await server.close(force: true);
    }
    if (mounted) setState(() {});
  }

  // ==========================================================================
  //  UTILIDADES DE INTERFAZ
  // ==========================================================================

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  ColorFilter _effectFilter() =>
      ColorFilter.matrix(kEffectMatrices[_s.effect]);

  Widget _frameOverlay({double inset = 10}) {
    final color = _s.frameResolvedColor;
    if (color == null) return const SizedBox.shrink();
    final neon = _s.neon;
    return IgnorePointer(
      child: Padding(
        padding: EdgeInsets.all(inset),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: color, width: neon ? 5 : 4),
            borderRadius: BorderRadius.circular(neon ? 8 : 16),
            boxShadow: neon
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.65),
                      blurRadius: 16,
                    ),
                  ]
                : const [],
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _stickerOverlay({double size = 54, double inset = 18}) {
    if (_s.sticker == 0) return const SizedBox.shrink();
    final set = kStickerSets[_s.sticker];
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: inset,
            right: inset,
            child: Text(set[0], style: TextStyle(fontSize: size)),
          ),
          Positioned(
            bottom: inset,
            left: inset,
            child: Text(set[1], style: TextStyle(fontSize: size)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: switch (_state) {
            BoothState.welcome => _welcomeScreen(),
            BoothState.camera => _cameraScreen(),
            BoothState.preview => _previewScreen(),
          },
        ),
      ),
    );
  }

  // ==========================================================================
  //  PANTALLA DE BIENVENIDA
  // ==========================================================================

  Widget _welcomeScreen() {
    final noCamera = widget.cameras.isEmpty;
    return Container(
      key: const ValueKey('welcome'),
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF25232B), Color(0xFF101014)],
        ),
      ),
      child: Stack(
        children: [
          OrientationBuilder(
            builder: (context, orientation) {
              final portrait = orientation == Orientation.portrait;
              final align =
                  portrait ? TextAlign.center : TextAlign.start;
              final content = Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: portrait
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  // Pulsación larga en el icono = acceso del operador.
                  GestureDetector(
                    onLongPress: _openOperatorSettings,
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 64,
                      color: gold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _s.eventName.toUpperCase(),
                    textAlign: align,
                    style: const TextStyle(
                      color: gold,
                      fontSize: 16,
                      letterSpacing: 4,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _s.welcomeText,
                    textAlign: align,
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Te haremos $_total fotos. Prepárate, sonríe y disfruta.',
                    textAlign: align,
                    style: const TextStyle(color: Colors.white70, fontSize: 18),
                  ),
                  const SizedBox(height: 32),
                  if (noCamera) ...[
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam_off_rounded, color: gold),
                        SizedBox(width: 8),
                        Text('No se detectó ninguna cámara.'),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  ScaleTransition(
                    scale: _pulseScale,
                    child: FilledButton.icon(
                      onPressed: _busy || noCamera ? null : _startSession,
                      icon: const Icon(Icons.play_arrow_rounded, size: 30),
                      label: Text(_busy ? 'PREPARANDO...' : 'COMENZAR'),
                      style: FilledButton.styleFrom(
                        backgroundColor: gold,
                        foregroundColor: Colors.black,
                        textStyle: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 44,
                          vertical: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              );
              return Padding(
                padding: const EdgeInsets.all(36),
                child: portrait
                    ? Center(child: content)
                    : Row(
                        children: [
                          Expanded(flex: 5, child: content),
                          const Expanded(
                            flex: 4,
                            child: Center(
                              child: Icon(
                                Icons.photo_camera_back_rounded,
                                size: 190,
                                color: Colors.white10,
                              ),
                            ),
                          ),
                        ],
                      ),
              );
            },
          ),
          // Acceso discreto para el operador.
          Positioned(
            right: 8,
            bottom: 8,
            child: IconButton(
              tooltip: 'Operador',
              onPressed: _openOperatorSettings,
              icon: const Icon(Icons.lock_outline, color: Colors.white24),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  //  PANEL DEL OPERADOR
  // ==========================================================================

  Future<bool> _askPin() async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Acceso del operador'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Contraseña',
            hintText: 'Introduce la clave del operador',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          onSubmitted: (_) =>
              Navigator.pop(dialogContext, controller.text == _s.pin),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text == _s.pin),
            child: const Text('ENTRAR'),
          ),
        ],
      ),
    );
    return accepted == true;
  }

  Future<void> _openOperatorSettings() async {
    if (_state != BoothState.welcome) {
      _message('Finaliza la sesión antes de cambiar la configuración.');
      return;
    }
    final allowed = await _askPin();
    if (!mounted) return;
    if (!allowed) {
      _message('Contraseña incorrecta o acceso cancelado.');
      return;
    }

    final temp = _s.copy();
    final eventController = TextEditingController(text: temp.eventName);
    final welcomeController = TextEditingController(text: temp.welcomeText);
    final footerController = TextEditingController(text: temp.footer);
    final pinController = TextEditingController();
    var resetStats = false;

    const swatches = <Color>[
      gold,
      Colors.white,
      Color(0xFFFF6FAE),
      Color(0xFF66BFFF),
      Color(0xFF39FFB6),
      Color(0xFFB69CFF),
    ];

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget choice(
            String label,
            int value,
            List<String> names,
            ValueChanged<int> onChanged,
          ) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<int>(
                key: ValueKey('$label-$value'),
                initialValue: value,
                isExpanded: true,
                decoration: InputDecoration(labelText: label),
                items: List.generate(
                  names.length,
                  (i) => DropdownMenuItem(value: i, child: Text(names[i])),
                ),
                onChanged: (v) {
                  if (v != null) setDialogState(() => onChanged(v));
                },
              ),
            );
          }

          Widget toggle(
            String title,
            String? subtitle,
            bool value,
            ValueChanged<bool> onChanged,
          ) {
            return SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(title),
              subtitle: subtitle == null
                  ? null
                  : Text(subtitle, style: const TextStyle(fontSize: 12)),
              value: value,
              onChanged: (v) => setDialogState(() => onChanged(v)),
            );
          }

          Widget section(String title, List<Widget> children,
              {bool open = false}) {
            return ExpansionTile(
              initiallyExpanded: open,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              shape: const Border(),
              collapsedShape: const Border(),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              children: children,
            );
          }

          return AlertDialog(
            title: const Text('Configuración del evento'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    section('Evento', [
                      TextField(
                        controller: eventController,
                        maxLength: 40,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del evento',
                          prefixIcon: Icon(Icons.celebration_outlined),
                        ),
                      ),
                      TextField(
                        controller: welcomeController,
                        maxLength: 60,
                        decoration: const InputDecoration(
                          labelText: 'Mensaje de bienvenida',
                          prefixIcon: Icon(Icons.waving_hand_outlined),
                        ),
                      ),
                      TextField(
                        controller: footerController,
                        maxLength: 50,
                        decoration: const InputDecoration(
                          labelText: 'Mensaje al pie de la foto',
                          prefixIcon: Icon(Icons.favorite_border),
                        ),
                      ),
                    ], open: true),
                    section('Aspecto de las fotos', [
                      choice('Formato de impresión', temp.layout.index,
                          kLayoutNames, (v) => temp.layout = BoothLayout.values[v]),
                      if (temp.layout == BoothLayout.strip) ...[
                        const Text('Fotos por tira'),
                        const SizedBox(height: 8),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 2, label: Text('2')),
                            ButtonSegment(value: 3, label: Text('3')),
                            ButtonSegment(value: 4, label: Text('4')),
                          ],
                          selected: {temp.photoCount},
                          onSelectionChanged: (v) =>
                              setDialogState(() => temp.photoCount = v.first),
                        ),
                        const SizedBox(height: 12),
                      ],
                      choice('Efecto de cámara', temp.effect, kEffectNames,
                          (v) => temp.effect = v),
                      choice('Marco fotográfico', temp.frame, kFrameNames,
                          (v) => temp.frame = v),
                      const Text('Color del marco personalizado'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        children: swatches
                            .map(
                              (color) => InkWell(
                                onTap: () => setDialogState(
                                    () => temp.frameColor = color),
                                borderRadius: BorderRadius.circular(30),
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: temp.frameColor == color
                                          ? Colors.white
                                          : Colors.white24,
                                      width: temp.frameColor == color ? 3 : 1,
                                    ),
                                  ),
                                  child: temp.frameColor == color
                                      ? const Icon(Icons.check,
                                          color: Colors.black, size: 18)
                                      : null,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                      choice('Adornos (emojis)', temp.sticker, kStickerNames,
                          (v) => temp.sticker = v),
                      choice('Color de fondo de la tira', temp.sheetBg,
                          kSheetNames, (v) => temp.sheetBg = v),
                    ]),
                    section('Sesión', [
                      const Text('Cuenta atrás'),
                      const SizedBox(height: 8),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 3, label: Text('3 s')),
                          ButtonSegment(value: 5, label: Text('5 s')),
                          ButtonSegment(value: 10, label: Text('10 s')),
                        ],
                        selected: {temp.countdown},
                        onSelectionChanged: (v) =>
                            setDialogState(() => temp.countdown = v.first),
                      ),
                      const SizedBox(height: 12),
                      choice(
                        'Cerrar sesión por inactividad',
                        max(0, kIdleOptions.indexOf(temp.idleSeconds)),
                        kIdleOptions.map((s) => '$s segundos').toList(),
                        (v) => temp.idleSeconds = kIdleOptions[v],
                      ),
                      toggle(
                        'Secuencia automática',
                        'Toma las fotos una tras otra. Si lo apagas, cada foto se hace con el botón.',
                        temp.autoSequence,
                        (v) => temp.autoSequence = v,
                      ),
                      toggle('Sonido de obturador', null, temp.shutterSound,
                          (v) => temp.shutterSound = v),
                      toggle(
                        'Voltear fotos de cámara frontal',
                        'Actívalo si la foto sale al revés respecto a la vista previa.',
                        temp.mirrorPhotos,
                        (v) => temp.mirrorPhotos = v,
                      ),
                    ]),
                    section('Impresión y compartir', [
                      toggle('Permitir imprimir', null, temp.printEnabled,
                          (v) => temp.printEnabled = v),
                      choice(
                        'Copias máximas por sesión',
                        temp.maxCopies - 1,
                        const ['1', '2', '3', '4', '5'],
                        (v) => temp.maxCopies = v + 1,
                      ),
                      toggle(
                        'Imprimir automáticamente 1 copia',
                        'Solo funciona con una impresora fija elegida.',
                        temp.autoPrint,
                        (v) => temp.autoPrint = v,
                      ),
                      toggle('Compartir por QR', null, temp.shareEnabled,
                          (v) => temp.shareEnabled = v),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              temp.printerUrl == null
                                  ? 'Impresora: diálogo de iOS en cada impresión'
                                  : 'Impresora fija: ${temp.printerName ?? temp.printerUrl}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final size = MediaQuery.sizeOf(context);
                              final picked = await Printing.pickPrinter(
                                context: context,
                                bounds: Rect.fromLTWH(
                                  size.width / 2 - 100,
                                  size.height / 2 - 20,
                                  200,
                                  40,
                                ),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  temp.printerUrl = picked.url;
                                  temp.printerName = picked.name;
                                });
                              }
                            },
                            child: const Text('ELEGIR'),
                          ),
                          if (temp.printerUrl != null)
                            IconButton(
                              tooltip: 'Quitar impresora fija',
                              onPressed: () => setDialogState(() {
                                temp.printerUrl = null;
                                temp.printerName = null;
                              }),
                              icon: const Icon(Icons.close),
                            ),
                        ],
                      ),
                    ]),
                    section('Seguridad y estadísticas', [
                      TextField(
                        controller: pinController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: 8,
                        decoration: const InputDecoration(
                          labelText:
                              'Nueva contraseña (opcional, mínimo 4 dígitos)',
                          prefixIcon: Icon(Icons.password),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        resetStats
                            ? 'Las estadísticas se pondrán a cero al guardar.'
                            : 'Sesiones: $_sessionsCount  ·  Copias impresas: $_printsCount',
                        style: const TextStyle(
                            fontSize: 13, color: Colors.white70),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                setDialogState(() => resetStats = true),
                            icon: const Icon(Icons.restart_alt),
                            label: const Text('PONER A CERO'),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setDialogState(() {
                                temp.restoreDefaults();
                                eventController.text = temp.eventName;
                                welcomeController.text = temp.welcomeText;
                                footerController.text = temp.footer;
                              });
                            },
                            icon: const Icon(Icons.settings_backup_restore),
                            label: const Text('VALORES POR DEFECTO'),
                          ),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 8),
                    const Text(
                      'El efecto, el marco y los adornos se aplican a la hoja final, '
                      'a la impresión y a la tira compartida por QR. '
                      'Las fotos individuales se comparten sin modificar.',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('CANCELAR'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.save_outlined),
                label: const Text('GUARDAR'),
              ),
            ],
          );
        },
      ),
    );

    if (!mounted || saved != true) return;

    final defaults = BoothSettings();
    final newPin = pinController.text.trim();
    var pinMessage = '';
    if (newPin.isNotEmpty) {
      if (newPin.length >= 4 && int.tryParse(newPin) != null) {
        temp.pin = newPin;
      } else {
        pinMessage = ' La contraseña nueva no es válida y no se cambió.';
      }
    }
    final name = eventController.text.trim();
    final welcome = welcomeController.text.trim();
    temp.eventName = name.isEmpty ? defaults.eventName : name;
    temp.welcomeText = welcome.isEmpty ? defaults.welcomeText : welcome;
    temp.footer = footerController.text.trim();
    if (resetStats) {
      _sessionsCount = 0;
      _printsCount = 0;
      await _saveStats();
    }
    setState(() => _s = temp);
    await temp.save(widget.prefs);
    _message('Configuración guardada.$pinMessage');
  }

  // ==========================================================================
  //  PANTALLA DE CÁMARA
  // ==========================================================================

  Widget _cameraScreen() {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return const Center(
        key: ValueKey('camera-loading'),
        child: CircularProgressIndicator(),
      );
    }
    return LayoutBuilder(
      key: const ValueKey('camera'),
      builder: (context, constraints) {
        final portrait = constraints.maxHeight > constraints.maxWidth;
        final view = _cameraView(camera);
        return Padding(
          padding: const EdgeInsets.all(12),
          child: portrait
              ? Column(
                  children: [
                    Expanded(child: view),
                    const SizedBox(height: 10),
                    _cameraControls(compact: true),
                  ],
                )
              : Row(
                  children: [
                    Expanded(flex: 5, child: view),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Center(child: _cameraControls(compact: false)),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _cameraView(CameraController camera) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        color: Colors.black,
        width: double.infinity,
        height: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // La vista previa rellena todo el recuadro (sin franjas negras).
            LayoutBuilder(
              builder: (context, _) {
                final landscape =
                    MediaQuery.orientationOf(context) == Orientation.landscape;
                final aspect = camera.value.aspectRatio;
                final ratio = landscape ? aspect : 1 / aspect;
                return ColorFiltered(
                  colorFilter: _effectFilter(),
                  child: ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: 1000 * ratio,
                        height: 1000,
                        child: CameraPreview(camera),
                      ),
                    ),
                  ),
                );
              },
            ),
            _frameOverlay(inset: 8),
            _stickerOverlay(),
            if (_countingDown)
              Container(
                color: Colors.black26,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: Text(
                        '$_countdown',
                        key: ValueKey(_countdown),
                        style: const TextStyle(
                          fontSize: 180,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(blurRadius: 24, color: Colors.black54),
                          ],
                        ),
                      ),
                    ),
                    const Text(
                      'Mira a la cámara',
                      style: TextStyle(
                        fontSize: 22,
                        shadows: [Shadow(blurRadius: 12, color: Colors.black87)],
                      ),
                    ),
                  ],
                ),
              ),
            if (_busy && !_countingDown && !_flash)
              const Center(child: CircularProgressIndicator()),
            // Flash de captura.
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _flash ? 1 : 0,
                duration: Duration(milliseconds: _flash ? 40 : 350),
                child: Container(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_total, (i) {
        final filled = i < _photos.length && i != _retakeIndex;
        return Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? gold : Colors.transparent,
            border: Border.all(color: gold, width: 2),
          ),
        );
      }),
    );
  }

  Widget _cameraControls({required bool compact}) {
    final retake = _retakeIndex;
    final label = retake != null
        ? 'REPITIENDO FOTO ${retake + 1}'
        : 'FOTO ${min(_photos.length + 1, _total)} DE $_total';
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!compact) const Icon(Icons.auto_awesome, color: gold, size: 38),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 16 : 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        _progressDots(),
        if (!compact) ...[
          const SizedBox(height: 8),
          Text(
            _s.eventName,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy || _countingDown ? null : _startCountdown,
          icon: const Icon(Icons.camera_alt),
          label: const Text('TOMAR FOTO'),
        ),
        if (widget.cameras.length > 1)
          TextButton.icon(
            onPressed: _busy || _countingDown ? null : _switchCamera,
            icon: const Icon(Icons.cameraswitch_rounded),
            label: const Text('CAMBIAR CÁMARA'),
          ),
        TextButton(
          onPressed: _busy ? null : _finishSession,
          child: const Text('CANCELAR'),
        ),
      ],
    );
  }

  // ==========================================================================
  //  PANTALLA DE RESULTADOS
  // ==========================================================================

  Widget _previewScreen() {
    return Listener(
      key: const ValueKey('preview'),
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _idleLeft = _s.idleSeconds,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final portrait = constraints.maxHeight > constraints.maxWidth;
            final gallery = _resultsGallery();
            final actions = _printPanel();
            if (portrait) {
              return Column(
                children: [
                  Expanded(flex: 5, child: gallery),
                  const SizedBox(height: 16),
                  Expanded(flex: 4, child: actions),
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 6, child: gallery),
                const SizedBox(width: 20),
                Expanded(flex: 4, child: actions),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _resultsGallery() {
    final sheet = _composite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '¡Tus recuerdos están listos!',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Center(
            child: sheet == null
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 14),
                      Text('Preparando tus fotos...'),
                    ],
                  )
                : AspectRatio(
                    aspectRatio: 2 / 3,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [
                          BoxShadow(color: Colors.black54, blurRadius: 24),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(sheet, fit: BoxFit.contain),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 84,
          child: Row(
            children: [
              for (var i = 0; i < _photos.length; i++) _thumbnail(i),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Toca una foto pequeña para repetirla.',
          style: TextStyle(fontSize: 12, color: Colors.white60),
        ),
      ],
    );
  }

  Widget _thumbnail(int index) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: GestureDetector(
          onTap: _busy ? null : () => _confirmRetake(index),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColorFiltered(
                  colorFilter: _effectFilter(),
                  child: Transform.flip(
                    flipX: _mirrorPhotos,
                    child: Image.file(
                      File(_photos[index].path),
                      fit: BoxFit.cover,
                      cacheWidth: 400,
                    ),
                  ),
                ),
                _frameOverlay(inset: 3),
                _stickerOverlay(size: 16, inset: 4),
                const Positioned(
                  right: 4,
                  bottom: 4,
                  child: Icon(Icons.replay_circle_filled_rounded, size: 22),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _printPanel() {
    final canPrint = _s.printEnabled;
    final canShare = _s.shareEnabled;
    final copies = min(_copies, _s.maxCopies);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canPrint) ...[
                const Icon(Icons.print_rounded, size: 40, color: gold),
                const SizedBox(height: 10),
                const Text(
                  'Imprime tu recuerdo',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                if (_s.maxCopies > 1)
                  DropdownButton<int>(
                    value: copies,
                    isExpanded: true,
                    items: List.generate(
                      _s.maxCopies,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('${i + 1} copia(s)'),
                      ),
                    ),
                    onChanged: (value) {
                      if (value != null) setState(() => _copies = value);
                    },
                  ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _busy || _composite == null ? null : _printPhotos,
                  icon: const Icon(Icons.print),
                  label: Text(_busy ? 'PREPARANDO...' : 'IMPRIMIR'),
                ),
                const SizedBox(height: 16),
              ],
              if (canShare) ...[
                if (_shareUrl != null) ...[
                  QrImageView(
                    data: _shareUrl!,
                    version: QrVersions.auto,
                    size: 150,
                    padding: const EdgeInsets.all(8),
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Escanea para ver y descargar tus fotos',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    _shareUrl!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 9, color: Colors.white54),
                  ),
                ] else ...[
                  const Icon(Icons.wifi_off_rounded, color: gold, size: 36),
                  const SizedBox(height: 8),
                  const Text(
                    'Conecta el iPad a la red local para activar el QR.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                  TextButton(
                    onPressed:
                        _busy || _composite == null ? null : _startPhotoServer,
                    child: const Text('REINTENTAR QR'),
                  ),
                ],
                const SizedBox(height: 16),
              ],
              if (!canPrint && !canShare) ...[
                const Icon(Icons.favorite_rounded, size: 40, color: gold),
                const SizedBox(height: 10),
                const Text(
                  '¡Gracias por pasarte por la fotocabina!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
              ],
              OutlinedButton.icon(
                onPressed: _busy ? null : _startSession,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('REPETIR TODAS'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _finishSession,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('FINALIZAR'),
              ),
              const SizedBox(height: 10),
              Text(
                'La sesión se cerrará sola en $_idleLeft s',
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
