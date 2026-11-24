(() => {
  let cameraStream = null;
  let poseDetector = null;
  let frameTimer = null;
  let processingFrame = false;
  let callback = null;

  const isArmExtended = (landmarks, shoulderIndex, elbowIndex, wristIndex) => {
    const shoulder = landmarks[shoulderIndex];
    const elbow = landmarks[elbowIndex];
    const wrist = landmarks[wristIndex];
    if (
      !shoulder ||
      !elbow ||
      !wrist ||
      shoulder.visibility < 0.35 ||
      elbow.visibility < 0.35 ||
      wrist.visibility < 0.35
    ) {
      return false;
    }

    const shoulderVector = {
      x: shoulder.x - elbow.x,
      y: shoulder.y - elbow.y,
    };
    const wristVector = {
      x: wrist.x - elbow.x,
      y: wrist.y - elbow.y,
    };
    const shoulderLength = Math.hypot(shoulderVector.x, shoulderVector.y);
    const wristLength = Math.hypot(wristVector.x, wristVector.y);
    if (shoulderLength === 0 || wristLength === 0) return false;

    const cosine = Math.max(
      -1,
      Math.min(
        1,
        (shoulderVector.x * wristVector.x +
          shoulderVector.y * wristVector.y) /
          (shoulderLength * wristLength),
      ),
    );
    const angle = (Math.acos(cosine) * 180) / Math.PI;
    const shoulderWidth = Math.abs(
      landmarks[11].x - landmarks[12].x,
    );
    const shoulderToWrist = Math.hypot(
      wrist.x - shoulder.x,
      wrist.y - shoulder.y,
    );
    return (
      angle > 150 &&
      shoulderToWrist > shoulderWidth * 0.55 &&
      wrist.y < shoulder.y + shoulderWidth * 0.18
    );
  };

  window.boxerStartPoseTracking = async (video, onPose) => {
    if (cameraStream) return;
    if (!navigator.mediaDevices?.getUserMedia) {
      throw new Error('Este navegador não oferece acesso à câmera.');
    }
    if (typeof window.Pose !== 'function') {
      throw new Error('O rastreador corporal não carregou. Verifique a conexão.');
    }

    callback = onPose;
    cameraStream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {
        facingMode: 'user',
        width: { ideal: 640 },
        height: { ideal: 480 },
        frameRate: { ideal: 24 },
      },
    });

    try {
      video.srcObject = cameraStream;
      await video.play();

      poseDetector = new window.Pose({
        locateFile: (file) =>
          `https://cdn.jsdelivr.net/npm/@mediapipe/pose/${file}`,
      });
      poseDetector.setOptions({
        modelComplexity: 0,
        smoothLandmarks: true,
        enableSegmentation: false,
        minDetectionConfidence: 0.55,
        minTrackingConfidence: 0.55,
      });
      poseDetector.onResults((results) => {
        const landmarks = results.poseLandmarks;
        const nose = landmarks?.[0];
        if (!landmarks || !nose) {
          callback?.(-1, 0, -1, -1, -1, -1, false, false, false);
          return;
        }

        const leftArmExtended = isArmExtended(landmarks, 11, 13, 15);
        const rightArmExtended = isArmExtended(landmarks, 12, 14, 16);
        const leftWrist = landmarks[15];
        const rightWrist = landmarks[16];
        callback?.(
          nose.x,
          nose.visibility ?? 0,
          leftWrist?.visibility >= 0.35 ? leftWrist.x : -1,
          leftWrist?.visibility >= 0.35 ? leftWrist.y : -1,
          rightWrist?.visibility >= 0.35 ? rightWrist.x : -1,
          rightWrist?.visibility >= 0.35 ? rightWrist.y : -1,
          leftArmExtended,
          rightArmExtended,
          true,
        );
      });

      frameTimer = window.setInterval(async () => {
        if (processingFrame || !poseDetector || video.readyState < 2) return;
        processingFrame = true;
        try {
          await poseDetector.send({ image: video });
        } catch (error) {
          console.error('Pose tracking frame failed:', error);
        } finally {
          processingFrame = false;
        }
      }, 50);
    } catch (error) {
      await window.boxerStopPoseTracking();
      throw error;
    }
  };

  window.boxerStopPoseTracking = async () => {
    if (frameTimer !== null) {
      window.clearInterval(frameTimer);
      frameTimer = null;
    }
    cameraStream?.getTracks().forEach((track) => track.stop());
    cameraStream = null;
    if (poseDetector) {
      await poseDetector.close();
      poseDetector = null;
    }
    processingFrame = false;
    callback = null;
  };
})();
