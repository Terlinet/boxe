import 'pose_tracking_stub.dart'
    if (dart.library.js_interop) 'pose_tracking_web.dart'
    as platform;
import 'pose_tracking_types.dart';

export 'pose_tracking_types.dart';

PoseTrackingController createPoseTrackingController({
  required TrackedPoseCallback onPose,
  required TrackingStatusCallback onStatus,
}) => platform.createPoseTrackingController(onPose: onPose, onStatus: onStatus);
