import 'package:flutter/material.dart';

import 'pose_tracking_types.dart';

PoseTrackingController createPoseTrackingController({
  required TrackedPoseCallback onPose,
  required TrackingStatusCallback onStatus,
}) => _UnsupportedPoseTrackingController(onStatus);

class _UnsupportedPoseTrackingController implements PoseTrackingController {
  _UnsupportedPoseTrackingController(this._onStatus);

  final TrackingStatusCallback _onStatus;

  @override
  Widget buildPreview() => const ColoredBox(
    color: Color(0xFF111827),
    child: Center(
      child: Icon(Icons.videocam_off_outlined, color: Color(0xFF00FFE0)),
    ),
  );

  @override
  Future<void> start() async {
    const message =
        'O reconhecimento por câmera não está disponível nesta plataforma.';
    _onStatus(message);
    throw UnsupportedError(message);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
