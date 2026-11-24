import 'package:flutter/widgets.dart';

class TrackedPose {
  const TrackedPose({
    required this.headX,
    required this.leftArmExtended,
    required this.rightArmExtended,
    this.leftHand,
    this.rightHand,
  });

  final double headX;
  final bool leftArmExtended;
  final bool rightArmExtended;
  final Offset? leftHand;
  final Offset? rightHand;
}

typedef TrackedPoseCallback = void Function(TrackedPose? pose);
typedef TrackingStatusCallback = void Function(String status);

abstract interface class PoseTrackingController {
  Widget buildPreview();

  Future<void> start();

  Future<void> stop();

  Future<void> dispose();
}
