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
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );
  final AudioPlayer _punchPlayer = AudioPlayer();
  late final AnimationController _punchAnimationController;
  late final AnimationController _enemyHitAnimationController;
  late final AnimationController _playerHitAnimationController;
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
  Offset? _leftHandPosition;
  Offset? _rightHandPosition;
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
    _enemyHitAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _playerHitAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
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
            unawaited(_animatePlayerHit());
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
        _leftHandPosition = null;
        _rightHandPosition = null;
        _setCameraStatus('Câmera ativa · mostre o rosto e os braços');
        _refreshFightView();
      } else {
        _setCameraStatus('Pessoa detectada · movimentos habilitados');
        _recognizeGestures(
          poses.first,
          image.width.toDouble(),
          image.height.toDouble(),
        );
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

  void _recognizeGestures(Pose pose, double frameWidth, double frameHeight) {
    final nose = pose.landmarks[PoseLandmarkType.nose];
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    _leftHandPosition = _normalizedHandPosition(
      pose.landmarks[PoseLandmarkType.leftWrist],
      frameWidth,
      frameHeight,
    );
    _rightHandPosition = _normalizedHandPosition(
      pose.landmarks[PoseLandmarkType.rightWrist],
      frameWidth,
      frameHeight,
    );
    if (nose != null) {
      _handleHeadPosition(nose.x / frameWidth);
    }

    if (leftShoulder == null || rightShoulder == null) {
      _recognizeArmExtensions(false, false);
      _refreshFightView();
      return;
    }
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

    _refreshFightView();
  }

  void _refreshFightView() {
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
      _leftHandPosition = null;
      _rightHandPosition = null;
      _refreshFightView();
      return;
    }

    _setCameraStatus('Pessoa detectada · gestos habilitados');
    _handleHeadPosition(pose.headX);
    _leftHandPosition = pose.leftHand;
    _rightHandPosition = pose.rightHand;
    _recognizeArmExtensions(pose.leftArmExtended, pose.rightArmExtended);

    final now = DateTime.now();
    if (now.difference(_lastScreenUpdate) > const Duration(milliseconds: 100)) {
      _lastScreenUpdate = now;
      setState(() {});
    }
  }

  Offset? _normalizedHandPosition(
    PoseLandmark? landmark,
    double frameWidth,
    double frameHeight,
  ) {
    if (landmark == null ||
        landmark.likelihood < 0.35 ||
        frameWidth <= 0 ||
        frameHeight <= 0) {
      return null;
    }
    final normalizedX = landmark.x / frameWidth;
    final normalizedY = landmark.y / frameHeight;
    if (normalizedX < 0 ||
        normalizedX > 1 ||
        normalizedY < 0 ||
        normalizedY > 1) {
      return null;
    }
    return Offset(1 - normalizedX, normalizedY);
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
    unawaited(_animateEnemyHit());
    if (_isFightOver) unawaited(_stopCamera());
  }

  Future<void> _animatePlayerPunch() async {
    await _punchAnimationController.forward(from: 0);
    if (mounted && !_isDisposed) {
      await _punchAnimationController.reverse();
    }
  }

  Future<void> _animateEnemyHit() async {
    await _enemyHitAnimationController.forward(from: 0);
    if (mounted && !_isDisposed) {
      await _enemyHitAnimationController.reverse();
    }
  }

  Future<void> _animatePlayerHit() async {
    await _playerHitAnimationController.forward(from: 0);
    if (mounted && !_isDisposed) {
      await _playerHitAnimationController.reverse();
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
    _enemyHitAnimationController.dispose();
    _playerHitAnimationController.dispose();
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
                    animation: Listenable.merge([
                      _punchAnimationController,
                      _enemyHitAnimationController,
                      _playerHitAnimationController,
                    ]),
                    builder: (context, child) => CustomPaint(
                      painter: BoxingRingPainter(
                        headOffset: _headOffset,
                        enemyAttacking: _enemyAttacking,
                        playerPunchProgress: _punchAnimationController.value,
                        playerPunchLeft: _playerPunchLeft,
                        leftHandPosition: _leftHandPosition,
                        rightHandPosition: _rightHandPosition,
                        enemyHealth: _enemyHealth,
                        enemyHitProgress: _enemyHitAnimationController.value,
                        playerHitProgress: _playerHitAnimationController.value,
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
    required this.leftHandPosition,
    required this.rightHandPosition,
    required this.enemyHealth,
    required this.enemyHitProgress,
    required this.playerHitProgress,
  });

  final double headOffset;
  final bool enemyAttacking;
  final double playerPunchProgress;
  final bool playerPunchLeft;
  final Offset? leftHandPosition;
  final Offset? rightHandPosition;
  final int enemyHealth;
  final double enemyHitProgress;
  final double playerHitProgress;

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

    final opponentX = centerX;
    _drawOpponent(
      canvas,
      Offset(opponentX, height * (enemyAttacking ? 0.42 : 0.39)),
      scale: width * (enemyAttacking ? 0.0058 : 0.0052),
      attacking: enemyAttacking,
    );
    _drawPlayerHead(canvas, size, headOffset);
    _drawPlayerGloves(
      canvas,
      size,
      progress: playerPunchProgress,
      leftPunch: playerPunchLeft,
      leftHandPosition: leftHandPosition,
      rightHandPosition: rightHandPosition,
    );
    _drawImpact(
      canvas,
      Offset(opponentX, height * 0.39),
      enemyHitProgress,
      width,
    );
    _drawImpact(
      canvas,
      Offset(
        centerX +
            (headOffset * width * 1.5).clamp(-width * 0.18, width * 0.18),
        height * 0.75,
      ),
      playerHitProgress,
      width,
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

  void _drawImpact(
    Canvas canvas,
    Offset center,
    double progress,
    double width,
  ) {
    if (progress <= 0) return;
    final eased = Curves.easeOut.transform(progress);
    final radius = width * (0.025 + eased * 0.055);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFFFFFFFF).withOpacity((1 - eased) * 0.82)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, width * 0.006),
    );
    canvas.drawCircle(
      center,
      radius * 0.38,
      Paint()
        ..color = const Color(0xFFFFCC00).withOpacity((1 - eased) * 0.9),
    );
  }

  void _drawPlayerHead(Canvas canvas, Size size, double headOffset) {
    final center = Offset(
      size.width / 2 +
          (headOffset * size.width * 1.5).clamp(
            -size.width * 0.18,
            size.width * 0.18,
          ),
      size.height * 0.75,
    );
    final unit = math.min(size.width * 0.012, size.height * 0.022);
    final headLean =
        headOffset.clamp(-1.0, 1.0).toDouble() * unit * 1.8;
    final backOfHead = center.translate(headLean, -unit * 4);

    canvas.save();
    canvas.translate(backOfHead.dx, backOfHead.dy);
    canvas.rotate(headLean / (unit * 18));
    canvas.translate(-backOfHead.dx, -backOfHead.dy);

    final neckRect = Rect.fromCenter(
      center: center.translate(headLean, unit * 7),
      width: unit * 10,
      height: unit * 14,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(neckRect, Radius.circular(unit * 3)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFFB57B60), Color(0xFF7F5041)],
        ).createShader(neckRect),
    );

    final headRect = Rect.fromCenter(
      center: backOfHead,
      width: unit * 20,
      height: unit * 22,
    );
    canvas.drawOval(
      headRect.inflate(unit * 1),
      Paint()..color = const Color(0xFF090B12).withOpacity(0.58),
    );
    canvas.drawOval(
      headRect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.25, -0.45),
          radius: 0.95,
          colors: const [
            Color(0xFFD9A789),
            Color(0xFFBC8063),
            Color(0xFF855744),
          ],
        ).createShader(headRect),
    );

    final hairRect = Rect.fromCenter(
      center: backOfHead.translate(0, -unit * 6),
      width: unit * 20,
      height: unit * 11,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(hairRect, Radius.circular(unit * 5)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFF211A28), Color(0xFF121019)],
        ).createShader(hairRect),
    );

    final hairLinePaint = Paint()
      ..color = const Color(0xFF352B3C).withOpacity(0.7)
      ..strokeWidth = unit * 0.55
      ..strokeCap = StrokeCap.round;
    for (var i = -3; i <= 3; i++) {
      final start = backOfHead.translate(i * unit * 2.2, -unit * 8);
      canvas.drawLine(
        start,
        start.translate(-unit * 0.7, unit * 5),
        hairLinePaint,
      );
    }

    final napePath = Path()
      ..moveTo(backOfHead.dx - unit * 8, backOfHead.dy + unit * 7)
      ..quadraticBezierTo(
        backOfHead.dx,
        backOfHead.dy + unit * 12,
        backOfHead.dx + unit * 8,
        backOfHead.dy + unit * 7,
      );
    canvas.drawPath(
      napePath,
      Paint()
        ..color = const Color(0xFF17131D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 1,
    );
    canvas.restore();

    final shoulderRect = Rect.fromCenter(
      center: center.translate(0, unit * 16),
      width: unit * 34,
      height: unit * 15,
    );
    canvas.drawOval(
      shoulderRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFF19C5C4), Color(0xFF08767A)],
        ).createShader(shoulderRect),
    );
  }

  void _drawOpponent(
    Canvas canvas,
    Offset center, {
    required double scale,
    required bool attacking,
  }) {
    final unit = scale;
    final lean = attacking ? unit * 2.5 : 0.0;
    final shadowRect = Rect.fromCenter(
      center: center.translate(lean, unit * 12),
      width: unit * 38,
      height: unit * 8,
    );
    canvas.drawOval(
      shadowRect,
      Paint()..color = const Color(0xFF05070D).withOpacity(0.55),
    );

    final skinRect = Rect.fromCenter(
      center: center.translate(lean, -unit * 20),
      width: unit * 17,
      height: unit * 22,
    );
    canvas.drawOval(
      skinRect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 0.95,
          colors: const [
            Color(0xFFFFD2A4),
            Color(0xFFE5A76F),
            Color(0xFFA96E48),
          ],
        ).createShader(skinRect),
    );

    final hairPath = Path()
      ..addOval(
        Rect.fromCenter(
          center: center.translate(lean, -unit * 28),
          width: unit * 18,
          height: unit * 9,
        ),
      );
    canvas.drawPath(hairPath, Paint()..color = const Color(0xFF24151F));

    for (final side in [-1.0, 1.0]) {
      final eye = center.translate(lean + side * unit * 4, -unit * 21);
      canvas.drawOval(
        Rect.fromCenter(
          center: eye,
          width: unit * 4.5,
          height: unit * 1.8,
        ),
        Paint()..color = const Color(0xFFE6E4D4),
      );
      canvas.drawCircle(
        eye,
        unit * 0.8,
        Paint()..color = const Color(0xFF20191B),
      );
      canvas.drawLine(
        eye.translate(-unit * 2.5, -unit * 1.5),
        eye.translate(unit * 2.5, -unit * 1.5),
        Paint()
          ..color = const Color(0xFF3A2424)
          ..strokeWidth = unit * 0.55
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.drawLine(
      center.translate(lean, -unit * 20),
      center.translate(lean, -unit * 13),
      Paint()
        ..color = const Color(0xFF9B6749)
        ..strokeWidth = unit * 0.75
        ..strokeCap = StrokeCap.round,
    );

    final torsoRect = Rect.fromCenter(
      center: center.translate(lean, -unit * 7),
      width: unit * 22,
      height: unit * 24,
    );
    canvas.drawOval(
      torsoRect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.45),
          radius: 1,
          colors: const [
            Color(0xFFFFD782),
            Color(0xFFDDA64E),
            Color(0xFF8C5A30),
          ],
        ).createShader(torsoRect),
    );
    canvas.drawLine(
      center.translate(lean, -unit * 15),
      center.translate(lean, unit * 2),
      Paint()
        ..color = const Color(0xFF9B702F).withOpacity(0.75)
        ..strokeWidth = unit * 0.7,
    );

    final shortsRect = Rect.fromCenter(
      center: center.translate(lean, unit * 8),
      width: unit * 25,
      height: unit * 12,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(shortsRect, Radius.circular(unit * 2)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [Color(0xFF38CED0), Color(0xFF08777B)],
        ).createShader(shortsRect),
    );

    for (final side in [-1.0, 1.0]) {
      final legRect = Rect.fromCenter(
        center: center.translate(lean + side * unit * 6, unit * 15),
        width: unit * 7,
        height: unit * 13,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(legRect, Radius.circular(unit * 2)),
        Paint()
          ..shader = LinearGradient(
            colors: const [Color(0xFFF0B477), Color(0xFFA96943)],
          ).createShader(legRect),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center.translate(lean + side * unit * 6, unit * 22),
            width: unit * 10,
            height: unit * 3,
          ),
          Radius.circular(unit),
        ),
        Paint()..color = const Color(0xFFF2EAD5),
      );

      final gloveCenter = center.translate(
        lean + side * (attacking ? unit * 16 : unit * 13),
        attacking ? -unit * 15 : -unit * 12,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: gloveCenter.translate(0, unit),
          width: unit * 9,
          height: unit * 7,
        ),
        Paint()..color = const Color(0xFF080A12),
      );
      final gloveRect = Rect.fromCenter(
        center: gloveCenter,
        width: unit * 8,
        height: unit * 6,
      );
      canvas.drawOval(
        gloveRect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.5),
            colors: const [Color(0xFFFF6B84), Color(0xFFE51B49)],
          ).createShader(gloveRect),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: gloveCenter.translate(-unit * 2, -unit * 1.5),
          width: unit * 3,
          height: unit * 1.5,
        ),
        Paint()..color = const Color(0xFFFFBEC7).withOpacity(0.75),
      );
    }
  }

  void _drawPlayerGloves(
    Canvas canvas,
    Size size, {
    required double progress,
    required bool leftPunch,
    required Offset? leftHandPosition,
    required Offset? rightHandPosition,
  }) {
    final block = math.min(size.width * 0.018, size.height * 0.035);
    final centerX = size.width / 2;
    final punch = Curves.easeInOut.transform(progress);
    final outline = Paint()..color = const Color(0xFF080A12);
    for (final isLeft in [true, false]) {
      final side = isLeft ? -1.0 : 1.0;
      final striking = isLeft == leftPunch;
      final movement = striking ? punch : punch * 0.12;
      final trackedHand = isLeft ? leftHandPosition : rightHandPosition;
      final restCenter = Offset(
        centerX + side * size.width * 0.25,
        size.height * 0.86,
      );
      final trackedCenter = trackedHand == null
          ? restCenter
          : Offset(
              trackedHand.dx * size.width,
              size.height * (0.2 + trackedHand.dy * 0.72),
            );
      final enemyTarget = Offset(
        centerX + (isLeft ? -size.width * 0.045 : size.width * 0.045),
        size.height * 0.42,
      );
      final gloveCenter = striking
          ? Offset.lerp(
              Offset.lerp(restCenter, trackedCenter, 0.88)!,
              enemyTarget,
              punch,
            )!
          : Offset.lerp(restCenter, trackedCenter, 0.88)! +
              Offset(
                (centerX - restCenter.dx) * movement * 0.28,
                -size.height * movement * 0.08,
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
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: const [Color(0xFF7E102D), Color(0xFFFF234F)],
          ).createShader(Rect.fromPoints(
            armStart,
            Offset(gloveCenter.dx, gloveCenter.dy + block * 1.5),
          ))
          ..strokeWidth = block * 6
          ..strokeCap = StrokeCap.square,
      );
      final shadowRect = Rect.fromCenter(
        center: gloveCenter.translate(0, block * 0.8),
        width: block * 13,
        height: block * 11,
      );
      canvas.drawOval(shadowRect, Paint()..color = outline.color);
      final gloveRect = Rect.fromCenter(
        center: gloveCenter,
        width: block * 11.5,
        height: block * 9.5,
      );
      canvas.drawOval(
        gloveRect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.5),
            radius: 0.9,
            colors: const [
              Color(0xFFFF7C91),
              Color(0xFFFF234F),
              Color(0xFF9F1235),
            ],
          ).createShader(gloveRect),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: gloveCenter.translate(-side * block * 2.2, -block * 2.3),
          width: block * 4.2,
          height: block * 2,
        ),
        Paint()..color = const Color(0xFFFFB8C2).withOpacity(0.82),
      );
    }
  }

  @override
  bool shouldRepaint(covariant BoxingRingPainter oldDelegate) =>
      oldDelegate.headOffset != headOffset ||
      oldDelegate.enemyAttacking != enemyAttacking ||
      oldDelegate.playerPunchProgress != playerPunchProgress ||
      oldDelegate.playerPunchLeft != playerPunchLeft ||
      oldDelegate.leftHandPosition != leftHandPosition ||
      oldDelegate.rightHandPosition != rightHandPosition ||
      oldDelegate.enemyHealth != enemyHealth ||
      oldDelegate.enemyHitProgress != enemyHitProgress ||
      oldDelegate.playerHitProgress != playerHitProgress;
}
