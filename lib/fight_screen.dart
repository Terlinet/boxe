import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'pose_tracking.dart';

class FightScreen extends StatefulWidget {
  const FightScreen({super.key});

  @override
  State<FightScreen> createState() => _FightScreenState();
}

class _FightScreenState extends State<FightScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );
  final AudioPlayer _punchPlayer = AudioPlayer();
  late final AnimationController _punchAnimationController;
  Future<void> _punchSoundQueue = Future<void>.value();
  PoseTrackingController? _webPoseController;

  CameraController? _cameraController;
  Timer? _attackTimer;
  Timer? _attackWindowTimer;
  bool _isStartingCamera = false;
  bool _isProcessingFrame = false;
  bool _isCameraReady = false;
  bool _isDisposed = false;
  bool _enemyAttacking = false;
  bool _playerPunchLeft = false;
  bool _dodgedCurrentAttack = false;
  bool _leftArmExtended = false;
  bool _rightArmExtended = false;
  int _playerHealth = 3;
  int _enemyHealth = 100;
  int _punches = 0;
  int _dodges = 0;
  String _cameraStatus = 'Preparando câmera...';
  String _combatMessage = 'Posicione-se diante da câmera';
  double? _headCenter;
  double _headOffset = 0;
  DateTime _lastHeadEvent = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPunchEvent = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastScreenUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _isFightOver => _playerHealth == 0 || _enemyHealth == 0;

  @override
  void initState() {
    super.initState();
    _punchAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      _webPoseController = createPoseTrackingController(
        onPose: _onWebPose,
        onStatus: _setCameraStatus,
      );
      unawaited(_startWebTracking());
    } else if (_supportsPoseDetection) {
      unawaited(_startCamera());
    } else {
      _cameraStatus =
          'O reconhecimento por câmera está disponível no Android e iOS.';
      _combatMessage = 'Use a versão móvel para iniciar uma luta';
    }
  }

  bool get _supportsPoseDetection =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _canTrackGestures => kIsWeb || _supportsPoseDetection;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_stopCamera());
    } else if (state == AppLifecycleState.resumed &&
        _canTrackGestures &&
        !_isFightOver) {
      unawaited(kIsWeb ? _startWebTracking() : _startCamera());
    }
  }

  Future<void> _startWebTracking() async {
    if (_isStartingCamera || _isDisposed || _isFightOver) return;
    _isStartingCamera = true;
    _setCameraStatus('Solicitando acesso à câmera...');
    try {
      await _webPoseController!.start();
      if (!mounted) return;
      setState(() {
        _isCameraReady = true;
        _cameraStatus = 'Câmera ativa · mostre o rosto e os braços';
        _combatMessage = 'Desvie com a cabeça e golpeie estendendo o braço';
      });
      _startAttackTimer();
    } on Exception catch (error) {
      _setCameraStatus('Falha ao iniciar a câmera: $error');
    } finally {
      _isStartingCamera = false;
    }
  }

  Future<void> _startCamera() async {
    if (_isStartingCamera || _isDisposed || _isFightOver) return;
    _isStartingCamera = true;
    _setCameraStatus('Solicitando acesso à câmera...');
    CameraController? controller;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setCameraStatus('Nenhuma câmera foi encontrada neste dispositivo.');
        return;
      }

      final camera = cameras.where(
        (description) => description.lensDirection == CameraLensDirection.front,
      );
      final description = camera.isNotEmpty ? camera.first : cameras.first;
      controller = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (_isDisposed) {
        await controller.dispose();
        return;
      }

      _cameraController = controller;
      await controller.startImageStream(_processCameraImage);
      if (!mounted) return;
      setState(() {
        _isCameraReady = true;
        _cameraStatus = 'Câmera ativa · mostre o rosto e os braços';
        _combatMessage = 'Desvie com a cabeça e golpeie estendendo o braço';
      });
      _startAttackTimer();
    } on CameraException catch (error) {
      if (controller != null && !identical(controller, _cameraController)) {
        await controller.dispose();
      }
      _setCameraStatus(_cameraErrorMessage(error));
    } on PlatformException catch (error) {
      if (controller != null && !identical(controller, _cameraController)) {
        await controller.dispose();
      }
      _setCameraStatus(
        'Não foi possível iniciar a câmera: ${error.message ?? error.code}',
      );
    } on Exception catch (error) {
      if (controller != null && !identical(controller, _cameraController)) {
        await controller.dispose();
      }
      _setCameraStatus('Falha ao iniciar a câmera: $error');
    } finally {
      _isStartingCamera = false;
    }
  }

  String _cameraErrorMessage(CameraException error) {
    if (error.code == 'CameraAccessDenied' ||
        error.code == 'CameraAccessDeniedWithoutPrompt') {
      return 'Permissão da câmera negada. Autorize o acesso nas configurações.';
    }
    return 'Erro de câmera (${error.code}): ${error.description ?? 'sem detalhes'}';
  }

  Future<void> _stopCamera() async {
    _attackTimer?.cancel();
    _attackWindowTimer?.cancel();
    if (kIsWeb) {
      await _webPoseController?.stop();
      _isCameraReady = false;
      return;
    }
    final controller = _cameraController;
    _cameraController = null;
    _isCameraReady = false;
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await controller.dispose();
    } on CameraException catch (error) {
      _setCameraStatus(_cameraErrorMessage(error));
    }
  }

  void _startAttackTimer() {
    _attackTimer?.cancel();
    _attackTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_isCameraReady || _isFightOver) return;
      _attackWindowTimer?.cancel();
      setState(() {
        _enemyAttacking = true;
        _dodgedCurrentAttack = false;
        _combatMessage = 'GOLPE INIMIGO! Desvie agora!';
      });
      _attackWindowTimer = Timer(const Duration(milliseconds: 1200), () {
        if (!mounted || !_enemyAttacking || _isFightOver) return;
        setState(() {
          _enemyAttacking = false;
          if (_dodgedCurrentAttack) {
            _dodges++;
            _combatMessage = 'ESQUIVA PERFEITA!';
          } else {
            _playerHealth = _playerHealth > 0 ? _playerHealth - 1 : 0;
            _combatMessage = _isFightOver
                ? 'Nocaute! A luta terminou.'
                : 'Você foi atingido! Mova a cabeça para os lados.';
          }
        });
        if (_isFightOver) unawaited(_stopCamera());
      });
    });
  }

  void _processCameraImage(CameraImage image) {
    if (_isProcessingFrame || _isDisposed || _isFightOver) return;
    _isProcessingFrame = true;
    unawaited(_detectPose(image));
  }

  Future<void> _detectPose(CameraImage image) async {
    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        _setCameraStatus('Formato de imagem da câmera não compatível.');
        return;
      }
      final poses = await _poseDetector.processImage(inputImage);
      if (poses.isEmpty) {
        _setCameraStatus('Câmera ativa · mostre o rosto e os braços');
      } else {
        _setCameraStatus('Pessoa detectada · movimentos habilitados');
        _recognizeGestures(poses.first, image.width.toDouble());
      }
    } on PlatformException catch (error) {
      _setCameraStatus(
        'Falha no reconhecimento de pose: ${error.message ?? error.code}',
      );
    } on Exception catch (error) {
      _setCameraStatus('Falha no reconhecimento de pose: $error');
    } finally {
      _isProcessingFrame = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final controller = _cameraController;
    if (controller == null) return null;

    final rotation = InputImageRotationValue.fromRawValue(
      controller.description.sensorOrientation,
    );
    if (rotation == null || image.planes.isEmpty) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    Uint8List bytes;
    InputImageFormat resolvedFormat = format;
    if (image.planes.length == 1) {
      bytes = image.planes.first.bytes;
    } else if (defaultTargetPlatform == TargetPlatform.android &&
        image.planes.length == 3 &&
        (format == InputImageFormat.yuv_420_888 ||
            format == InputImageFormat.yv12)) {
      bytes = _convertYuv420ToNv21(image);
      resolvedFormat = InputImageFormat.nv21;
    } else {
      return null;
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: resolvedFormat,
        bytesPerRow: resolvedFormat == InputImageFormat.nv21
            ? image.width
            : image.planes.first.bytesPerRow,
      ),
    );
  }

  Uint8List _convertYuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final output = Uint8List(width * height + (width * height ~/ 2));
    var outputIndex = 0;

    for (var row = 0; row < height; row++) {
      final rowStart = row * yPlane.bytesPerRow;
      for (var column = 0; column < width; column++) {
        output[outputIndex++] = yPlane.bytes[rowStart + column];
      }
    }

    for (var row = 0; row < height ~/ 2; row++) {
      for (var column = 0; column < width ~/ 2; column++) {
        final uIndex =
            row * uPlane.bytesPerRow + column * (uPlane.bytesPerPixel ?? 1);
        final vIndex =
            row * vPlane.bytesPerRow + column * (vPlane.bytesPerPixel ?? 1);
        output[outputIndex++] = vPlane.bytes[vIndex];
        output[outputIndex++] = uPlane.bytes[uIndex];
      }
    }
    return output;
  }

  void _recognizeGestures(Pose pose, double frameWidth) {
    final nose = pose.landmarks[PoseLandmarkType.nose];
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    if (nose != null) {
      _handleHeadPosition(nose.x / frameWidth);
    }

    if (leftShoulder == null || rightShoulder == null) return;
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    if (shoulderWidth <= 0) return;
    final leftExtended = _isArmExtended(
      pose,
      shoulder: PoseLandmarkType.leftShoulder,
      elbow: PoseLandmarkType.leftElbow,
      wrist: PoseLandmarkType.leftWrist,
      shoulderWidth: shoulderWidth,
    );
    final rightExtended = _isArmExtended(
      pose,
      shoulder: PoseLandmarkType.rightShoulder,
      elbow: PoseLandmarkType.rightElbow,
      wrist: PoseLandmarkType.rightWrist,
      shoulderWidth: shoulderWidth,
    );
    _recognizeArmExtensions(leftExtended, rightExtended);

    final now = DateTime.now();
    if (mounted &&
        now.difference(_lastScreenUpdate) > const Duration(milliseconds: 100)) {
      _lastScreenUpdate = now;
      setState(() {});
    }
  }

  void _onWebPose(TrackedPose? pose) {
    if (!mounted || _isDisposed) return;
    if (pose == null) {
      _leftArmExtended = false;
      _rightArmExtended = false;
      return;
    }

    _setCameraStatus('Pessoa detectada · gestos habilitados');
    _handleHeadPosition(pose.headX);
    _recognizeArmExtensions(pose.leftArmExtended, pose.rightArmExtended);

    final now = DateTime.now();
    if (now.difference(_lastScreenUpdate) > const Duration(milliseconds: 100)) {
      _lastScreenUpdate = now;
      setState(() {});
    }
  }

  void _handleHeadPosition(double headX) {
    _headCenter ??= headX;
    _headOffset = headX - _headCenter!;
    final now = DateTime.now();
    if (_headOffset.abs() > 0.075 &&
        now.difference(_lastHeadEvent) > const Duration(milliseconds: 700)) {
      _lastHeadEvent = now;
      if (_enemyAttacking) _dodgedCurrentAttack = true;
      _setCombatMessage(_enemyAttacking ? 'ESQUIVA!' : 'Boa movimentação!');
    }
  }

  void _recognizeArmExtensions(bool leftExtended, bool rightExtended) {
    final leftPunched = leftExtended && !_leftArmExtended;
    final rightPunched = rightExtended && !_rightArmExtended;
    _leftArmExtended = leftExtended;
    _rightArmExtended = rightExtended;

    if (leftPunched || rightPunched) _registerPunch(left: leftPunched);
  }

  void _registerPunch({required bool left}) {
    if (DateTime.now().difference(_lastPunchEvent) <=
            const Duration(milliseconds: 450) ||
        !mounted ||
        _isFightOver) {
      return;
    }

    _lastPunchEvent = DateTime.now();
    _punchSoundQueue = _punchSoundQueue.then((_) => _playPunchSound());
    _playerPunchLeft = left;
    setState(() {
      _punches++;
      _enemyHealth = _enemyHealth > 12 ? _enemyHealth - 12 : 0;
      _combatMessage = _isFightOver ? 'Nocaute! Você venceu!' : 'DIRETO!';
    });
    unawaited(_animatePlayerPunch());
    if (_isFightOver) unawaited(_stopCamera());
  }

  Future<void> _animatePlayerPunch() async {
    await _punchAnimationController.forward(from: 0);
    if (mounted && !_isDisposed) {
      await _punchAnimationController.reverse();
    }
  }

  Future<void> _playPunchSound() async {
    try {
      await _punchPlayer.stop();
      await _punchPlayer.play(AssetSource('soco.mp3'));
    } on PlatformException catch (error) {
      _setCombatMessage(
        'Não foi possível tocar o som do soco: ${error.message ?? error.code}',
      );
    } on Exception catch (error) {
      _setCombatMessage('Não foi possível tocar o som do soco: $error');
    }
  }

  bool _isArmExtended(
    Pose pose, {
    required PoseLandmarkType shoulder,
    required PoseLandmarkType elbow,
    required PoseLandmarkType wrist,
    required double shoulderWidth,
  }) {
    final shoulderPoint = pose.landmarks[shoulder];
    final elbowPoint = pose.landmarks[elbow];
    final wristPoint = pose.landmarks[wrist];
    if (shoulderPoint == null ||
        elbowPoint == null ||
        wristPoint == null ||
        shoulderPoint.likelihood < 0.35 ||
        elbowPoint.likelihood < 0.35 ||
        wristPoint.likelihood < 0.35) {
      return false;
    }

    final shoulderX = shoulderPoint.x - elbowPoint.x;
    final shoulderY = shoulderPoint.y - elbowPoint.y;
    final wristX = wristPoint.x - elbowPoint.x;
    final wristY = wristPoint.y - elbowPoint.y;
    final shoulderLength = math.sqrt(
      shoulderX * shoulderX + shoulderY * shoulderY,
    );
    final wristLength = math.sqrt(wristX * wristX + wristY * wristY);
    if (shoulderLength == 0 || wristLength == 0) return false;

    final cosine =
        ((shoulderX * wristX + shoulderY * wristY) /
                (shoulderLength * wristLength))
            .clamp(-1.0, 1.0);
    final angle = math.acos(cosine) * 180 / math.pi;
    final shoulderToWrist = math.sqrt(
      math.pow(wristPoint.x - shoulderPoint.x, 2) +
          math.pow(wristPoint.y - shoulderPoint.y, 2),
    );
    return angle > 150 &&
        shoulderToWrist > shoulderWidth * 0.55 &&
        wristPoint.y < shoulderPoint.y + shoulderWidth * 0.18;
  }

  void _setCameraStatus(String status) {
    if (!mounted || _cameraStatus == status) return;
    setState(() => _cameraStatus = status);
  }

  void _setCombatMessage(String message) {
    if (!mounted || _combatMessage == message) return;
    setState(() => _combatMessage = message);
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _attackTimer?.cancel();
    _attackWindowTimer?.cancel();
    _punchAnimationController.dispose();
    final controller = _cameraController;
    if (controller != null) unawaited(controller.dispose());
    if (kIsWeb) {
      final webPoseController = _webPoseController;
      if (webPoseController != null) unawaited(webPoseController.dispose());
    } else {
      unawaited(_poseDetector.close());
    }
    unawaited(_punchSoundQueue.then((_) => _punchPlayer.dispose()));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cameraController = _cameraController;
    return Scaffold(
      backgroundColor: const Color(0xFF080A12),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 10),
              _buildHealthBars(),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF00FFE0).withOpacity(0.65),
                    ),
                  ),
                  child: AnimatedBuilder(
                    animation: _punchAnimationController,
                    builder: (context, child) => CustomPaint(
                      painter: BoxingRingPainter(
                        headOffset: _headOffset,
                        enemyAttacking: _enemyAttacking,
                        playerPunchProgress: _punchAnimationController.value,
                        playerPunchLeft: _playerPunchLeft,
                        enemyHealth: _enemyHealth,
                      ),
                      child: child,
                    ),
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.66),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: Text(
                            _combatMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFFFCC00),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _buildCameraPreview(cameraController),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    _isCameraReady ? Icons.circle : Icons.info_outline,
                    size: 12,
                    color: _isCameraReady
                        ? const Color(0xFF00FF66)
                        : const Color(0xFFFFCC00),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _cameraStatus,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (!_isCameraReady && _canTrackGestures)
                    TextButton(
                      onPressed: _isStartingCamera
                          ? null
                          : kIsWeb
                          ? _startWebTracking
                          : _startCamera,
                      child: const Text('TENTAR'),
                    ),
                ],
              ),
              if (_isFightOver) _buildGameOverActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
          color: const Color(0xFF00FFE0),
        ),
        const Expanded(
          child: Text(
            'RING // ARENA 01',
            style: TextStyle(
              color: Color(0xFF00FFE0),
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ),
        Text(
          'SCORE ${(_punches * 100 + _dodges * 50).toString().padLeft(4, '0')}',
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildHealthBars() {
    return Row(
      children: [
        Expanded(
          child: _HealthBar(
            label: 'OPONENTE',
            value: _enemyHealth / 100,
            color: const Color(0xFFFF0055),
          ),
        ),
        const SizedBox(width: 16),
        Row(
          children: List.generate(
            3,
            (index) => Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.favorite,
                size: 18,
                color: index < _playerHealth
                    ? const Color(0xFFFF3366)
                    : Colors.white24,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraPreview(CameraController? controller) {
    final ready =
        controller != null && controller.value.isInitialized && _isCameraReady;
    return Container(
      height: 172,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF0055).withOpacity(0.65)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (kIsWeb && _isCameraReady)
            _webPoseController!.buildPreview()
          else if (ready)
            CameraPreview(controller)
          else
            const Center(
              child: Icon(
                Icons.videocam_off_outlined,
                color: Color(0xFF00FFE0),
                size: 42,
              ),
            ),
          Align(
            alignment: Alignment.topLeft,
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: Colors.black54,
              child: const Text(
                'PLAYER CAM // POSE TRACKING',
                style: TextStyle(
                  color: Color(0xFF00FFE0),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameOverActions() {
    final won = _enemyHealth == 0;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            won ? 'VITÓRIA' : 'DERROTA',
            style: TextStyle(
              color: won ? const Color(0xFF00FF66) : const Color(0xFFFF0055),
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 18),
          TextButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(builder: (_) => const FightScreen()),
            ),
            child: const Text('NOVA LUTA'),
          ),
        ],
      ),
    );
  }
}

class _HealthBar extends StatelessWidget {
  const _HealthBar({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 9,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            color: color,
            backgroundColor: Colors.white12,
          ),
        ),
      ],
    );
  }
}

class BoxingRingPainter extends CustomPainter {
  const BoxingRingPainter({
    required this.headOffset,
    required this.enemyAttacking,
    required this.playerPunchProgress,
    required this.playerPunchLeft,
    required this.enemyHealth,
  });

  final double headOffset;
  final bool enemyAttacking;
  final double playerPunchProgress;
  final bool playerPunchLeft;
  final int enemyHealth;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final background = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF202548), Color(0xFF111528), Color(0xFF090B14)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(bounds);
    canvas.drawRect(bounds, background);

    final width = size.width;
    final height = size.height;
    final horizon = height * 0.34;
    final centerX = width / 2;
    final ringFloor = Path()
      ..moveTo(width * 0.08, horizon)
      ..lineTo(width * 0.92, horizon)
      ..lineTo(width, height)
      ..lineTo(0, height)
      ..close();
    canvas.drawPath(ringFloor, Paint()..color = const Color(0xFF28314A));
    canvas.drawPath(
      ringFloor,
      Paint()
        ..color = const Color(0xFF00FFE0).withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final pixel = Paint()..color = const Color(0xFF00FFE0).withOpacity(0.55);
    for (var i = 0; i < 44; i++) {
      final x = ((i * 73 + 19) % 997) / 997 * width;
      final y = ((i * 47 + 13) % 281) / 1000 * height;
      canvas.drawRect(Rect.fromLTWH(x, y, 3, 3), pixel);
    }

    final floorLine = Paint()
      ..color = const Color(0xFF00FFE0).withOpacity(0.16)
      ..strokeWidth = 1;
    for (var i = 1; i <= 5; i++) {
      final t = i / 6;
      final y = horizon + (height - horizon) * t * t;
      canvas.drawLine(Offset(0, y), Offset(width, y), floorLine);
    }
    for (final edge in [0.08, 0.92]) {
      canvas.drawLine(
        Offset(centerX, horizon),
        Offset(width * edge, height),
        floorLine,
      );
    }

    final ropePaint = Paint()
      ..color = const Color(0xFFFF3366)
      ..strokeWidth = 2;
    for (var i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(width * 0.08, horizon + i * height * 0.105),
        Offset(width * 0.92, horizon + i * height * 0.105),
        ropePaint,
      );
    }
    for (final x in [width * 0.08, width * 0.92]) {
      canvas.drawLine(
        Offset(centerX, horizon),
        Offset(x, height * 0.72),
        Paint()
          ..color = const Color(0xFFFFCC00)
          ..strokeWidth = 4,
      );
    }

    final opponentX = (centerX - headOffset * width * 0.65)
        .clamp(width * 0.3, width * 0.7)
        .toDouble();
    _drawOpponent(
      canvas,
      Offset(opponentX, height * (enemyAttacking ? 0.42 : 0.39)),
      scale: width * (enemyAttacking ? 0.0058 : 0.0052),
      attacking: enemyAttacking,
    );
    _drawPlayerGloves(
      canvas,
      size,
      progress: playerPunchProgress,
      leftPunch: playerPunchLeft,
    );

    if (enemyHealth == 0) {
      final knockout = Paint()..color = const Color(0xFFFFCC00);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(opponentX - width * 0.025, height * 0.43),
          width: width * 0.14,
          height: width * 0.14,
        ),
        knockout,
      );
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(opponentX + width * 0.06, height * 0.46),
          width: width * 0.09,
          height: width * 0.09,
        ),
        knockout,
      );
    }
  }

  void _drawOpponent(
    Canvas canvas,
    Offset center, {
    required double scale,
    required bool attacking,
  }) {
    final block = scale;
    final lean = attacking ? block * 3 : 0.0;
    final outline = Paint()..color = const Color(0xFF070913);
    final shorts = Paint()..color = const Color(0xFF00B8BE);
    final skin = Paint()..color = const Color(0xFFFFC184);
    final glove = Paint()..color = const Color(0xFFFF244F);
    final shoe = Paint()..color = const Color(0xFFF4E7C4);

    void rect(double x, double y, double w, double h, Paint paint) {
      canvas.drawRect(
        Rect.fromLTWH(
          center.dx + x * block + lean,
          center.dy + y * block,
          w * block,
          h * block,
        ),
        paint,
      );
    }

    rect(-8, -27, 16, 8, outline);
    rect(-7, -26, 14, 8, skin);
    rect(-8, -28, 16, 3, Paint()..color = const Color(0xFF54314D));
    rect(-2, -23, 2, 1, outline);
    rect(4, -23, 2, 1, outline);
    rect(-5, -18, 10, 4, outline);
    rect(-7, -16, 14, 15, Paint()..color = const Color(0xFFFFCC00));
    rect(-9, -15, 3, 10, skin);
    rect(6, -15, 3, 10, skin);
    rect(-8, -12, 16, 10, outline);
    rect(-7, -11, 14, 9, Paint()..color = const Color(0xFFDA1642));
    rect(-8, -3, 16, 5, shorts);
    rect(-7, 2, 5, 8, outline);
    rect(2, 2, 5, 8, outline);
    rect(-8, 9, 7, 2, shoe);
    rect(2, 9, 7, 2, shoe);
    rect(-12, -16, 4, 5, outline);
    rect(8, -16, 4, 5, outline);
    rect(-12, -15, 4, 4, glove);
    rect(8, -15, 4, 4, glove);
    if (attacking) {
      rect(7, -14, 8, 3, outline);
      rect(9, -13, 8, 4, glove);
      rect(13, -12, 2, 2, Paint()..color = const Color(0xFFFFA09C));
    }
  }

  void _drawPlayerGloves(
    Canvas canvas,
    Size size, {
    required double progress,
    required bool leftPunch,
  }) {
    final block = math.min(size.width * 0.018, size.height * 0.035);
    final centerX = size.width / 2;
    final punch = Curves.easeInOut.transform(progress);
    final outline = Paint()..color = const Color(0xFF080A12);
    final red = Paint()..color = const Color(0xFFFF234F);
    final shine = Paint()..color = const Color(0xFFFFA3AD);
    final forearm = Paint()..color = const Color(0xFFBD1743);

    for (final isLeft in [true, false]) {
      final side = isLeft ? -1.0 : 1.0;
      final striking = isLeft == leftPunch;
      final movement = striking ? punch : punch * 0.12;
      final restCenter = Offset(
        centerX + side * size.width * 0.25,
        size.height * 0.86,
      );
      final gloveCenter = Offset(
        restCenter.dx + (centerX - restCenter.dx) * movement * 0.72,
        restCenter.dy - size.height * movement * 0.24,
      );
      final armStart = Offset(
        centerX + side * size.width * 0.38,
        size.height * 0.98,
      );
      canvas.drawLine(
        armStart,
        Offset(gloveCenter.dx, gloveCenter.dy + block * 1.5),
        Paint()
          ..color = outline.color
          ..strokeWidth = block * 8
          ..strokeCap = StrokeCap.square,
      );
      canvas.drawLine(
        armStart,
        Offset(gloveCenter.dx, gloveCenter.dy + block * 1.5),
        Paint()
          ..color = forearm.color
          ..strokeWidth = block * 6
          ..strokeCap = StrokeCap.square,
      );
      canvas.drawRect(
        Rect.fromCenter(
          center: gloveCenter,
          width: block * 11,
          height: block * 9,
        ),
        outline,
      );
      canvas.drawRect(
        Rect.fromCenter(
          center: gloveCenter.translate(-side * block * 0.4, -block * 0.25),
          width: block * 9,
          height: block * 7,
        ),
        red,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          gloveCenter.dx - block * 2.8,
          gloveCenter.dy - block * 2.3,
          block * 3.5,
          block * 1.6,
        ),
        shine,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BoxingRingPainter oldDelegate) =>
      oldDelegate.headOffset != headOffset ||
      oldDelegate.enemyAttacking != enemyAttacking ||
      oldDelegate.playerPunchProgress != playerPunchProgress ||
      oldDelegate.playerPunchLeft != playerPunchLeft ||
      oldDelegate.enemyHealth != enemyHealth;
}
