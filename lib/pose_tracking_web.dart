import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'pose_tracking_types.dart';

@JS('boxerStartPoseTracking')
external JSPromise<JSAny?> _startPoseTracking(
  web.HTMLVideoElement video,
  JSFunction onPose,
);

@JS('boxerStopPoseTracking')
external JSPromise<JSAny?> _stopPoseTracking();

int _nextPreviewId = 0;

PoseTrackingController createPoseTrackingController({
  required TrackedPoseCallback onPose,
  required TrackingStatusCallback onStatus,
}) => _WebPoseTrackingController(onPose, onStatus);

class _WebPoseTrackingController implements PoseTrackingController {
  _WebPoseTrackingController(this._onPose, this._onStatus) {
    _viewType = 'boxer-pose-camera-${_nextPreviewId++}';
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _video,
    );
  }

  final TrackedPoseCallback _onPose;
  final TrackingStatusCallback _onStatus;
  final web.HTMLVideoElement _video = web.HTMLVideoElement()
    ..autoplay = true
    ..muted = true
    ..setAttribute('playsinline', '')
    ..style.objectFit = 'cover'
    ..style.transform = 'scaleX(-1)'
    ..style.width = '100%'
    ..style.height = '100%';

  late final String _viewType;
  bool _isRunning = false;
  bool _isDisposed = false;

  @override
  Widget buildPreview() => HtmlElementView(viewType: _viewType);

  @override
  Future<void> start() async {
    if (_isRunning) return;
    _onStatus('Solicitando permissão da câmera...');
    try {
      await _startPoseTracking(_video, _receivePose.toJS).toDart;
    } catch (error) {
      throw StateError('Não foi possível iniciar o reconhecimento: $error');
    }
    if (_isDisposed) {
      await _stopPoseTracking().toDart;
      return;
    }
    _isRunning = true;
  }

  void _receivePose(
    JSNumber headX,
    JSNumber visibility,
    JSNumber leftHandX,
    JSNumber leftHandY,
    JSNumber rightHandX,
    JSNumber rightHandY,
    JSBoolean leftArmExtended,
    JSBoolean rightArmExtended,
    JSBoolean hasPose,
  ) {
    if (_isDisposed) return;
    if (!hasPose.toDart) {
      _onPose(null);
      _onStatus('Câmera ativa · mostre o rosto e os braços');
      return;
    }

    if (visibility.toDartDouble < 0.35) {
      _onPose(null);
      _onStatus('Câmera ativa · rosto não visível');
      return;
    }

    _onPose(
      TrackedPose(
        headX: 1 - headX.toDartDouble,
        leftArmExtended: leftArmExtended.toDart,
        rightArmExtended: rightArmExtended.toDart,
        leftHand: _normalizedHandPosition(
          leftHandX.toDartDouble,
          leftHandY.toDartDouble,
        ),
        rightHand: _normalizedHandPosition(
          rightHandX.toDartDouble,
          rightHandY.toDartDouble,
        ),
      ),
    );
    _onStatus('Pessoa detectada · gestos habilitados');
  }

  Offset? _normalizedHandPosition(double x, double y) {
    if (x < 0 || x > 1 || y < 0 || y > 1) return null;
    return Offset(1 - x, y);
  }

  @override
  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    await _stopPoseTracking().toDart;
    _onPose(null);
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    await stop();
    _video.removeAttribute('src');
  }
}
