/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamSessionViewModel.swift
//
// Core view model demonstrating video streaming from Meta wearable devices using the DAT SDK.
// This class showcases the key streaming patterns: device selection, session management,
// video frame handling, photo capture, and error handling.
//

import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import MWDATCamera
import MWDATCore
import SwiftUI
import VideoToolbox

enum StreamingStatus {
  case streaming
  case waiting
  case stopped
}

enum StreamingMode {
  case glasses
  case iPhone
}

enum IPhoneCameraPosition {
  case back
  case front
}

@MainActor
class StreamSessionViewModel: ObservableObject {
  @Published var currentVideoFrame: UIImage?
  @Published var hasReceivedFirstFrame: Bool = false
  @Published var streamingStatus: StreamingStatus = .stopped
  @Published var showError: Bool = false
  @Published var errorMessage: String = ""
  @Published var hasActiveDevice: Bool = false
  @Published var streamingMode: StreamingMode = .glasses
  @Published var selectedResolution: StreamingResolution = .low
  @Published var iPhoneCameraPosition: IPhoneCameraPosition = .back

  var isStreaming: Bool {
    streamingStatus != .stopped
  }

  var resolutionLabel: String {
    switch selectedResolution {
    case .low: return "360x640"
    case .medium: return "504x896"
    case .high: return "720x1280"
    @unknown default: return "Unknown"
    }
  }

  // Photo capture properties
  @Published var capturedPhoto: UIImage?
  @Published var showPhotoPreview: Bool = false

  // Gemini Live integration
  var geminiSessionVM: GeminiSessionViewModel?

  // WebRTC Live streaming integration
  var webrtcSessionVM: WebRTCSessionViewModel?

  // The core DAT SDK device session - owns the connection to the physical device.
  private var deviceSession: DeviceSession?
  // The camera capability attached to the device session - handles streaming operations.
  private var stream: MWDATCamera.Stream?
  // Listener tokens are used to manage DAT SDK event subscriptions
  private var sessionStateListenerToken: AnyListenerToken?
  private var sessionErrorListenerToken: AnyListenerToken?
  private var stateListenerToken: AnyListenerToken?
  private var videoFrameListenerToken: AnyListenerToken?
  private var errorListenerToken: AnyListenerToken?
  private var photoDataListenerToken: AnyListenerToken?
  private let wearables: WearablesInterface
  private let deviceSelector: AutoDeviceSelector
  private var deviceMonitorTask: Task<Void, Never>?
  private var iPhoneCameraManager: IPhoneCameraManager?

  // CPU-based CIContext for rendering decoded pixel buffers in background
  private let cpuCIContext = CIContext(options: [.useSoftwareRenderer: true])
  // VideoDecoder for decompressing HEVC/H.264 frames in background
  private let videoDecoder = VideoDecoder()
  private var backgroundFrameCount = 0
  private var bgDiagLogged = false

  init(wearables: WearablesInterface) {
    self.wearables = wearables
    // Let the SDK auto-select from available devices
    self.deviceSelector = AutoDeviceSelector(wearables: wearables)

    // Monitor device availability
    deviceMonitorTask = Task { @MainActor in
      for await device in deviceSelector.activeDeviceStream() {
        self.hasActiveDevice = device != nil
      }
    }

    setupVideoDecoder()
  }

  private func currentStreamConfiguration() -> StreamConfiguration {
    // NOTE: hvc1 caused the device to emit .videoStreamingError right after
    // stream.start(). Sticking with .raw — background decoding still works
    // via the pixel-buffer branch in attachStreamListeners.
    StreamConfiguration(
      videoCodec: VideoCodec.raw,
      resolution: selectedResolution,
      frameRate: 24)
  }

  private func setupVideoDecoder() {
    videoDecoder.setFrameCallback { [weak self] decodedFrame in
      Task { @MainActor [weak self] in
        guard let self else { return }
        let pixelBuffer = decodedFrame.pixelBuffer
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        if let cgImage = self.cpuCIContext.createCGImage(ciImage, from: rect) {
          let image = UIImage(cgImage: cgImage)
          self.geminiSessionVM?.sendVideoFrameIfThrottled(image: image)
          self.webrtcSessionVM?.pushVideoFrame(image)
          if self.backgroundFrameCount <= 5 || self.backgroundFrameCount % 120 == 0 {
            Log.stream.debug("Background frame #\(self.backgroundFrameCount) decoded and forwarded (\(width)x\(height))")
          }
        }
      }
    }
  }

  /// Drop the current session/stream so the next startSession() recreates them
  /// with the current selectedResolution. Only call when not actively streaming.
  func updateResolution(_ resolution: StreamingResolution) {
    guard !isStreaming else { return }
    selectedResolution = resolution
    stream = nil
    deviceSession = nil
    Log.stream.info("Resolution changed to \(self.resolutionLabel, privacy: .public)")
  }

  private func attachSessionListeners(_ session: DeviceSession) {
    sessionStateListenerToken = session.statePublisher.listen { [weak self] state in
      Task { @MainActor [weak self] in
        guard let self else { return }
        Log.stream.info("session state -> \(String(describing: state), privacy: .public)")
        if state == .stopped {
          self.streamingStatus = .stopped
          self.currentVideoFrame = nil
        }
      }
    }

    sessionErrorListenerToken = session.errorPublisher.listen { [weak self] error in
      Task { @MainActor [weak self] in
        guard let self else { return }
        Log.stream.error("session error: \(String(describing: error), privacy: .public) (description: \(error.description, privacy: .public))")
        showError(formatSessionError(error))
        // Any session-level error means the session is no longer trustworthy.
        // Drop it so the next start attempt creates a fresh one instead of
        // reusing a corpse.
        self.teardownSession()
      }
    }
  }

  private func attachStreamListeners(_ stream: MWDATCamera.Stream) {
    // Subscribe to stream state changes using the DAT SDK listener pattern
    stateListenerToken = stream.statePublisher.listen { [weak self] state in
      Task { @MainActor [weak self] in
        self?.updateStatusFromState(state)
      }
    }

    // Subscribe to video frames from the device camera
    // This callback fires whether the app is in the foreground or background,
    // enabling continuous streaming even when the screen is locked.
    videoFrameListenerToken = stream.videoFramePublisher.listen { [weak self] videoFrame in
      Task { @MainActor [weak self] in
        guard let self else { return }

        let isInBackground = UIApplication.shared.applicationState == .background

        if !isInBackground {
          self.backgroundFrameCount = 0
          self.bgDiagLogged = false
          if let image = videoFrame.makeUIImage() {
            self.currentVideoFrame = image
            if !self.hasReceivedFirstFrame {
              self.hasReceivedFirstFrame = true
            }
            self.geminiSessionVM?.sendVideoFrameIfThrottled(image: image)
            self.webrtcSessionVM?.pushVideoFrame(image)
          }
        } else {
          // In background: makeUIImage() uses VideoToolbox GPU rendering which iOS suspends.
          // Instead, use our VideoDecoder (VTDecompressionSession) to decode compressed
          // frames into pixel buffers, then convert via CPU CIContext.
          self.backgroundFrameCount += 1

          let sampleBuffer = videoFrame.sampleBuffer
          let hasCompressedData = CMSampleBufferGetDataBuffer(sampleBuffer) != nil

          if hasCompressedData {
            // Compressed frame (HEVC/H.264) - decode via VTDecompressionSession
            do {
              try self.videoDecoder.decode(sampleBuffer)
            } catch {
              if self.backgroundFrameCount <= 5 || self.backgroundFrameCount % 120 == 0 {
                Log.stream.error("Background frame #\(self.backgroundFrameCount) decode error: \(String(describing: error), privacy: .public)")
              }
            }
          } else if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            // Raw pixel buffer - convert directly via CPU CIContext
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            if let cgImage = self.cpuCIContext.createCGImage(ciImage, from: rect) {
              let image = UIImage(cgImage: cgImage)
              self.geminiSessionVM?.sendVideoFrameIfThrottled(image: image)
              self.webrtcSessionVM?.pushVideoFrame(image)
            }
            self.videoDecoder.invalidateSession()
          }
        }
      }
    }

    // Subscribe to streaming errors
    errorListenerToken = stream.errorPublisher.listen { [weak self] error in
      Task { @MainActor [weak self] in
        guard let self else { return }
        Log.stream.error("errorPublisher fired: \(String(describing: error), privacy: .public) (status=\(String(describing: self.streamingStatus), privacy: .public), codec=\(String(describing: self.currentStreamConfiguration().videoCodec), privacy: .public), resolution=\(self.resolutionLabel, privacy: .public))")
        // Suppress device-not-found errors when user hasn't started streaming yet
        if self.streamingStatus == .stopped {
          if case .deviceNotConnected = error { return }
          if case .deviceNotFound = error { return }
        }
        let newErrorMessage = formatStreamingError(error)
        if newErrorMessage != self.errorMessage {
          showError(newErrorMessage)
        }
        // The stream just failed — reusing this session on the next start
        // attempt typically fails silently (session stays in a non-.started
        // state and never streams). Tear it down so retry gets fresh state.
        self.teardownSession()
      }
    }

    updateStatusFromState(stream.state)

    // Subscribe to photo capture events
    photoDataListenerToken = stream.photoDataPublisher.listen { [weak self] photoData in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let uiImage = UIImage(data: photoData.data) {
          self.capturedPhoto = uiImage
          self.showPhotoPreview = true
        }
      }
    }
  }

  func handleStartStreaming() async {
    let permission = Permission.camera
    do {
      let status = try await wearables.checkPermissionStatus(permission)
      if status == .granted {
        await startSession()
        return
      }
      let requestStatus = try await wearables.requestPermission(permission)
      if requestStatus == .granted {
        await startSession()
        return
      }
      showError("Permission denied")
    } catch {
      showError("Permission error: \(error.description)")
    }
  }

  func startSession() async {
    guard streamingMode == .glasses else { return }
    streamingStatus = .waiting

    // Wait for a device to become available before creating a session.
    if deviceSelector.activeDevice == nil {
      Log.stream.info("startSession: waiting for active device")
      for await device in deviceSelector.activeDeviceStream() {
        if device != nil { break }
      }
    }
    Log.stream.info("startSession: active device present, cached session state=\(self.deviceSession.map { String(describing: $0.state) } ?? "nil", privacy: .public)")

    // Only reuse an existing session when it's in a state we can actually
    // start from. Anything else (stopping, paused, started-but-not-streaming,
    // or a stale post-error session) gets torn down first so we get a fresh
    // one below.
    if let existing = deviceSession {
      switch existing.state {
      case .idle, .stopped, .started:
        break
      default:
        Log.stream.notice("Dropping unusable cached session (state=\(String(describing: existing.state), privacy: .public))")
        teardownSession()
      }
    }

    do {
      let session: DeviceSession
      if let existing = deviceSession {
        session = existing
      } else {
        session = try wearables.createSession(deviceSelector: deviceSelector)
        deviceSession = session
        attachSessionListeners(session)
        Log.stream.info("Created new device session")
      }

      if session.state == .idle || session.state == .stopped {
        Log.stream.info("Calling session.start() from state=\(String(describing: session.state), privacy: .public)")
        try session.start()
      }

      // DeviceSession.start() is synchronous in DAT SDK 0.8 — it only kicks the
      // state machine (idle → starting → started). addStream() requires the
      // session to actually be started, otherwise it returns nil.
      if session.state != .started {
        var reachedStarted = false
        for await state in session.stateStream() {
          Log.stream.debug("awaiting .started, got \(String(describing: state), privacy: .public)")
          if state == .started {
            reachedStarted = true
            break
          }
          if state == .stopped {
            break
          }
        }
        guard reachedStarted else {
          Log.stream.error("session never reached .started (final state=\(String(describing: session.state), privacy: .public))")
          showError("Device session failed to start.")
          teardownSession()
          return
        }
      }

      guard let newStream = try session.addStream(config: currentStreamConfiguration()) else {
        Log.stream.error("addStream returned nil (session state: \(String(describing: session.state), privacy: .public))")
        showError("Unable to start camera stream.")
        teardownSession()
        return
      }
      stream = newStream
      attachStreamListeners(newStream)
      Log.stream.info("Calling stream.start() (codec=\(String(describing: self.currentStreamConfiguration().videoCodec), privacy: .public), resolution=\(self.resolutionLabel, privacy: .public))")
      newStream.start()
    } catch {
      Log.stream.error("DeviceSessionError: \(error.description, privacy: .public)")
      showError("Failed to start session: \(error.description)")
      teardownSession()
    }
  }

  private func showError(_ message: String) {
    errorMessage = message
    showError = true
  }

  func stopSession() async {
    if streamingMode == .iPhone {
      stopIPhoneSession()
      return
    }
    teardownSession()
  }

  private func teardownSession() {
    stream?.stop()
    deviceSession?.stop()
    stream = nil
    deviceSession = nil
    stateListenerToken = nil
    videoFrameListenerToken = nil
    errorListenerToken = nil
    photoDataListenerToken = nil
    sessionStateListenerToken = nil
    sessionErrorListenerToken = nil
    streamingStatus = .stopped
    currentVideoFrame = nil
    hasReceivedFirstFrame = false
  }

  // MARK: - iPhone Camera Mode

  func handleStartIPhone() async {
    let granted = await IPhoneCameraManager.requestPermission()
    if granted {
      startIPhoneSession()
    } else {
      showError("Camera permission denied. Please grant access in Settings.")
    }
  }

  private func startIPhoneSession() {
    streamingMode = .iPhone
    iPhoneCameraPosition = .back
    pinchBaseZoom = 1.0
    let camera = IPhoneCameraManager()
    camera.onFrameCaptured = { [weak self] image in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.currentVideoFrame = image
        if !self.hasReceivedFirstFrame {
          self.hasReceivedFirstFrame = true
        }
        self.geminiSessionVM?.sendVideoFrameIfThrottled(image: image)
        self.webrtcSessionVM?.pushVideoFrame(image)
      }
    }
    camera.onPositionChanged = { [weak self] position in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.iPhoneCameraPosition = position == .front ? .front : .back
        // Zoom factor resets to 1.0 on the newly activated device.
        self.pinchBaseZoom = 1.0
      }
    }
    camera.start()
    iPhoneCameraManager = camera
    streamingStatus = .streaming
    Log.stream.info("iPhone camera mode started")
  }

  private func stopIPhoneSession() {
    iPhoneCameraManager?.stop()
    iPhoneCameraManager = nil
    currentVideoFrame = nil
    hasReceivedFirstFrame = false
    streamingStatus = .stopped
    streamingMode = .glasses
    iPhoneCameraPosition = .back
    pinchBaseZoom = 1.0
    Log.stream.info("iPhone camera mode stopped")
  }

  // MARK: - iPhone Camera Controls

  /// Toggle between front and back cameras. No-op unless we're in iPhone mode.
  func switchIPhoneCamera() {
    iPhoneCameraManager?.switchCamera()
  }

  /// Focus at a normalized point in the portrait preview (origin top-left, [0,1]).
  func focusIPhoneCamera(atNormalizedPortraitPoint point: CGPoint) {
    iPhoneCameraManager?.setFocus(atNormalizedPortraitPoint: point)
  }

  /// Continuous-zoom helper for a `MagnificationGesture`.
  /// Call `beginIPhoneZoom()` at gesture start and `updateIPhoneZoom(scale:)` on change.
  func beginIPhoneZoom() {
    pinchBaseZoom = iPhoneCameraManager?.currentZoomFactor ?? 1.0
  }

  func updateIPhoneZoom(scale: CGFloat) {
    guard let camera = iPhoneCameraManager else { return }
    camera.setZoom(factor: pinchBaseZoom * scale)
  }

  private var pinchBaseZoom: CGFloat = 1.0

  func dismissError() {
    showError = false
    errorMessage = ""
  }

  func capturePhoto() {
    stream?.capturePhoto(format: .jpeg)
  }

  func dismissPhotoPreview() {
    showPhotoPreview = false
    capturedPhoto = nil
  }

  private func updateStatusFromState(_ state: StreamState) {
    switch state {
    case .stopped:
      currentVideoFrame = nil
      streamingStatus = .stopped
    case .waitingForDevice, .starting, .stopping, .paused:
      streamingStatus = .waiting
    case .streaming:
      streamingStatus = .streaming
    }
  }

  private func formatStreamingError(_ error: StreamError) -> String {
    switch error {
    case .internalError:
      return "An internal error occurred. Please try again."
    case .deviceNotFound:
      return "Device not found. Please ensure your device is connected."
    case .deviceNotConnected:
      return "Device not connected. Please check your connection and try again."
    case .timeout:
      return "The operation timed out. Please try again."
    case .videoStreamingError:
      return "Video streaming failed. Please try again."
    case .permissionDenied:
      return "Camera permission denied. Please grant permission in Settings."
    case .hingesClosed:
      return "The hinges on the glasses were closed. Please open the hinges and try again."
    case .thermalCritical, .thermalEmergency:
      return "The glasses are too warm to keep streaming. Let them cool down and try again."
    case .peakPowerShutdown:
      return "The glasses shut down streaming to protect the battery. Please try again."
    case .batteryCritical:
      return "The glasses battery is critically low. Please charge them and try again."
    @unknown default:
      return "An unknown streaming error occurred."
    }
  }

  private func formatSessionError(_ error: DeviceSessionError) -> String {
    switch error {
    case .noEligibleDevice:
      return "No compatible device found. Please ensure your glasses are connected."
    case .datAppOnTheGlassesUpdateRequired:
      return "Please update the Meta AI app on your glasses to continue."
    case .thermalCritical, .thermalEmergency:
      return "The glasses are too warm to keep streaming. Let them cool down and try again."
    case .peakPowerShutdown:
      return "The glasses shut down streaming to protect the battery. Please try again."
    case .batteryCritical:
      return "The glasses battery is critically low. Please charge them and try again."
    case .unexpectedError(let description):
      return description
    case .sessionAlreadyExists, .sessionAlreadyStopped, .sessionIdle, .capabilityAlreadyActive,
      .capabilityNotFound, .dwaUnavailable:
      return "A device session error occurred. Please try again."
    }
  }
}
