import AVFoundation
import UIKit

class IPhoneCameraManager: NSObject {
  private let captureSession = AVCaptureSession()
  private let videoOutput = AVCaptureVideoDataOutput()
  private let sessionQueue = DispatchQueue(label: "iphone-camera-session")
  private let context = CIContext()
  private var isRunning = false

  private var currentInput: AVCaptureDeviceInput?
  private(set) var currentPosition: AVCaptureDevice.Position = .back

  var onFrameCaptured: ((UIImage) -> Void)?
  var onPositionChanged: ((AVCaptureDevice.Position) -> Void)?

  func start() {
    guard !isRunning else { return }
    sessionQueue.async { [weak self] in
      self?.configureSession()
      self?.captureSession.startRunning()
      self?.isRunning = true
    }
  }

  func stop() {
    guard isRunning else { return }
    sessionQueue.async { [weak self] in
      self?.captureSession.stopRunning()
      self?.isRunning = false
    }
  }

  private func configureSession() {
    captureSession.beginConfiguration()
    captureSession.sessionPreset = .medium

    guard configureInput(position: currentPosition) else {
      captureSession.commitConfiguration()
      return
    }

    // Add video output
    videoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
    videoOutput.alwaysDiscardsLateVideoFrames = true

    if captureSession.canAddOutput(videoOutput) {
      captureSession.addOutput(videoOutput)
    }

    applyOutputOrientation()

    captureSession.commitConfiguration()
    Log.iPhoneCamera.info("Session configured")
  }

  @discardableResult
  private func configureInput(position: AVCaptureDevice.Position) -> Bool {
    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
          let input = try? AVCaptureDeviceInput(device: camera) else {
      Log.iPhoneCamera.error("Failed to access camera at position \(position.rawValue)")
      return false
    }

    if let existing = currentInput {
      captureSession.removeInput(existing)
    }

    guard captureSession.canAddInput(input) else {
      Log.iPhoneCamera.error("Session cannot add input for position \(position.rawValue)")
      // Try to restore previous input so we don't leave the session broken.
      if let existing = currentInput, captureSession.canAddInput(existing) {
        captureSession.addInput(existing)
      }
      return false
    }

    captureSession.addInput(input)
    currentInput = input
    currentPosition = position
    return true
  }

  private func applyOutputOrientation() {
    // Force portrait-oriented frames from the sensor
    guard let connection = videoOutput.connection(with: .video) else { return }
    if connection.isVideoRotationAngleSupported(90) {
      connection.videoRotationAngle = 90
    }
  }

  // MARK: - Camera controls

  /// Switch between the back and front cameras. No-op if the session hasn't started.
  func switchCamera() {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      let newPosition: AVCaptureDevice.Position = self.currentPosition == .back ? .front : .back
      self.captureSession.beginConfiguration()
      let ok = self.configureInput(position: newPosition)
      self.applyOutputOrientation()
      self.captureSession.commitConfiguration()
      if ok {
        let position = self.currentPosition
        DispatchQueue.main.async {
          self.onPositionChanged?(position)
        }
        Log.iPhoneCamera.info("Switched to \(position == .front ? "front" : "back", privacy: .public) camera")
      }
    }
  }

  /// Focus (and expose) at a point in the displayed portrait image, normalized to [0, 1].
  /// Origin is top-left of the portrait frame.
  func setFocus(atNormalizedPortraitPoint point: CGPoint) {
    let clamped = CGPoint(
      x: min(max(point.x, 0), 1),
      y: min(max(point.y, 0), 1)
    )
    sessionQueue.async { [weak self] in
      guard let self, let device = self.currentInput?.device else { return }

      // AVCaptureDevice expects focus points in the sensor's landscape coordinate space
      // where (0,0) is top-left in landscape-right orientation. We display frames rotated
      // 90° into portrait, so translate accordingly.
      let sensorPoint = CGPoint(x: clamped.y, y: 1.0 - clamped.x)

      do {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if device.isFocusPointOfInterestSupported {
          device.focusPointOfInterest = sensorPoint
        }
        if device.isFocusModeSupported(.autoFocus) {
          device.focusMode = .autoFocus
        } else if device.isFocusModeSupported(.continuousAutoFocus) {
          device.focusMode = .continuousAutoFocus
        }

        if device.isExposurePointOfInterestSupported {
          device.exposurePointOfInterest = sensorPoint
        }
        if device.isExposureModeSupported(.autoExpose) {
          device.exposureMode = .autoExpose
        } else if device.isExposureModeSupported(.continuousAutoExposure) {
          device.exposureMode = .continuousAutoExposure
        }
      } catch {
        Log.iPhoneCamera.error("Failed to set focus point: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /// Set the video zoom factor. The value is clamped to the device's supported range.
  func setZoom(factor: CGFloat) {
    sessionQueue.async { [weak self] in
      guard let self, let device = self.currentInput?.device else { return }
      let minZoom = device.minAvailableVideoZoomFactor
      // Cap at 8x to avoid extreme digital zoom values on ultra-wide capable devices.
      let maxZoom = min(device.maxAvailableVideoZoomFactor, 8.0)
      let clamped = min(max(factor, minZoom), maxZoom)
      do {
        try device.lockForConfiguration()
        device.videoZoomFactor = clamped
        device.unlockForConfiguration()
      } catch {
        Log.iPhoneCamera.error("Failed to set zoom: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /// Current zoom factor of the active device (defaults to 1.0 if unavailable).
  var currentZoomFactor: CGFloat {
    currentInput?.device.videoZoomFactor ?? 1.0
  }

  static func requestPermission() async -> Bool {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    switch status {
    case .authorized:
      return true
    case .notDetermined:
      return await AVCaptureDevice.requestAccess(for: .video)
    default:
      return false
    }
  }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension IPhoneCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
    let image = UIImage(cgImage: cgImage)

    onFrameCaptured?(image)
  }
}
