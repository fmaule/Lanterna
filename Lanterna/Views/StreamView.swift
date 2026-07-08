/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamView.swift
//
// Main UI for video streaming from Meta wearable devices using the DAT SDK.
// This view demonstrates the complete streaming API: video streaming with real-time display, photo capture,
// and error handling. Extended with Gemini Live AI assistant and WebRTC live streaming integration.
//

import MWDATCore
import SwiftUI

struct StreamView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel
  @ObservedObject var geminiVM: GeminiSessionViewModel
  @ObservedObject var webrtcVM: WebRTCSessionViewModel

  // Focus indicator state for iPhone tap-to-focus.
  @State private var focusIndicatorPoint: CGPoint?
  @State private var focusIndicatorTask: Task<Void, Never>?

  var body: some View {
    ZStack {
      // Black background for letterboxing/pillarboxing
      Color.black
        .edgesIgnoringSafeArea(.all)

      // Video backdrop: PiP when WebRTC connected, otherwise single local feed
      if webrtcVM.isActive && webrtcVM.connectionState == .connected {
        PiPVideoView(
          localFrame: viewModel.currentVideoFrame,
          remoteVideoTrack: webrtcVM.remoteVideoTrack,
          hasRemoteVideo: webrtcVM.hasRemoteVideo,
          mirrorLocal: viewModel.streamingMode == .iPhone
            && viewModel.iPhoneCameraPosition == .front
        )
      } else if let videoFrame = viewModel.currentVideoFrame, viewModel.hasReceivedFirstFrame {
        GeometryReader { geometry in
          ZStack {
            Image(uiImage: videoFrame)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: geometry.size.width, height: geometry.size.height)
              .clipped()

            if viewModel.streamingMode == .iPhone {
              // Transparent gesture surface for tap-to-focus and pinch-to-zoom.
              Color.clear
                .contentShape(Rectangle())
                .gesture(
                  MagnificationGesture()
                    .onChanged { scale in
                      viewModel.updateIPhoneZoom(scale: scale)
                    }
                    .onEnded { _ in
                      viewModel.beginIPhoneZoom()
                    }
                )
                .simultaneousGesture(
                  SpatialTapGesture()
                    .onEnded { value in
                      handleFocusTap(
                        at: value.location,
                        viewSize: geometry.size,
                        imageSize: videoFrame.size
                      )
                    }
                )

              if let point = focusIndicatorPoint {
                FocusIndicator()
                  .position(point)
                  .allowsHitTesting(false)
              }
            }
          }
          .frame(width: geometry.size.width, height: geometry.size.height)
          // Mirror the front camera preview so it feels natural (like the iOS Camera app).
          // Applied to the whole ZStack so gesture coordinates stay aligned with the
          // un-mirrored sensor image the AVCaptureDevice actually sees.
          .scaleEffect(x: viewModel.iPhoneCameraPosition == .front ? -1 : 1, y: 1)
        }
        .edgesIgnoringSafeArea(.all)
      } else {
        ProgressView()
          .scaleEffect(1.5)
          .foregroundColor(.white)
      }

      // Gemini status overlay (top) + speaking indicator
      if geminiVM.isGeminiActive {
        VStack {
          GeminiStatusBar(geminiVM: geminiVM)
          Spacer()

          VStack(spacing: 8) {
            if !geminiVM.userTranscript.isEmpty || !geminiVM.aiTranscript.isEmpty {
              TranscriptView(
                userText: geminiVM.userTranscript,
                aiText: geminiVM.aiTranscript
              )
            }

            ToolCallStatusView(status: geminiVM.toolCallStatus)

            if geminiVM.isModelSpeaking {
              HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                  .foregroundColor(.white)
                  .font(.system(size: 14))
                SpeakingIndicator()
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
              .background(Color.black.opacity(0.5))
              .cornerRadius(20)
            }
          }
          .padding(.bottom, 80)
        }
        .padding(.all, 24)
      }

      // WebRTC status overlay (top)
      if webrtcVM.isActive {
        VStack {
          WebRTCStatusBar(webrtcVM: webrtcVM)
          Spacer()
        }
        .padding(.all, 24)
      }

      // Bottom controls layer
      VStack {
        Spacer()
        ControlsView(viewModel: viewModel, geminiVM: geminiVM, webrtcVM: webrtcVM)
      }
      .padding(.all, 24)
    }
    .onDisappear {
      Task {
        if viewModel.streamingStatus != .stopped {
          await viewModel.stopSession()
        }
        if geminiVM.isGeminiActive {
          geminiVM.stopSession()
        }
        if webrtcVM.isActive {
          webrtcVM.stopSession()
        }
      }
    }
    // Show captured photos from DAT SDK in a preview sheet
    .sheet(isPresented: $viewModel.showPhotoPreview) {
      if let photo = viewModel.capturedPhoto {
        PhotoPreviewView(
          photo: photo,
          onDismiss: {
            viewModel.dismissPhotoPreview()
          }
        )
      }
    }
    // Gemini error alert
    .alert("AI Assistant", isPresented: Binding(
      get: { geminiVM.errorMessage != nil },
      set: { if !$0 { geminiVM.errorMessage = nil } }
    )) {
      Button("OK") { geminiVM.errorMessage = nil }
    } message: {
      Text(geminiVM.errorMessage ?? "")
    }
    // WebRTC error alert
    .alert("Live Stream", isPresented: Binding(
      get: { webrtcVM.errorMessage != nil },
      set: { if !$0 { webrtcVM.errorMessage = nil } }
    )) {
      Button("OK") { webrtcVM.errorMessage = nil }
    } message: {
      Text(webrtcVM.errorMessage ?? "")
    }
  }

  /// Convert a tap location in the display view (aspect-fill) into a normalized
  /// portrait image point, then forward it to the camera manager.
  private func handleFocusTap(at tap: CGPoint, viewSize: CGSize, imageSize: CGSize) {
    guard imageSize.width > 0, imageSize.height > 0,
          viewSize.width > 0, viewSize.height > 0 else { return }

    let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
    let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    let offset = CGPoint(
      x: (viewSize.width - scaledSize.width) / 2,
      y: (viewSize.height - scaledSize.height) / 2
    )

    let imagePoint = CGPoint(
      x: (tap.x - offset.x) / scale,
      y: (tap.y - offset.y) / scale
    )
    let normalized = CGPoint(
      x: min(max(imagePoint.x / imageSize.width, 0), 1),
      y: min(max(imagePoint.y / imageSize.height, 0), 1)
    )

    viewModel.focusIPhoneCamera(atNormalizedPortraitPoint: normalized)

    // Show focus indicator briefly at the tap location.
    focusIndicatorPoint = tap
    focusIndicatorTask?.cancel()
    focusIndicatorTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 800_000_000)
      if !Task.isCancelled {
        focusIndicatorPoint = nil
      }
    }
  }
}

/// Yellow reticle drawn briefly where the user tapped to focus.
private struct FocusIndicator: View {
  @State private var scale: CGFloat = 1.4
  @State private var opacity: Double = 0.0

  var body: some View {
    RoundedRectangle(cornerRadius: 4)
      .stroke(Color.yellow, lineWidth: 1.5)
      .frame(width: 72, height: 72)
      .scaleEffect(scale)
      .opacity(opacity)
      .onAppear {
        withAnimation(.easeOut(duration: 0.2)) {
          scale = 1.0
          opacity = 1.0
        }
        withAnimation(.easeIn(duration: 0.4).delay(0.4)) {
          opacity = 0.0
        }
      }
  }
}

// Extracted controls for clarity
struct ControlsView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var geminiVM: GeminiSessionViewModel
  @ObservedObject var webrtcVM: WebRTCSessionViewModel

  var body: some View {
    // Controls row
    HStack(spacing: 8) {
      CustomButton(
        title: "Stop streaming",
        style: .destructive,
        isDisabled: false
      ) {
        Task {
          await viewModel.stopSession()
        }
      }

      // Photo button (glasses mode only -- DAT SDK capture)
      if viewModel.streamingMode == .glasses {
        CircleButton(icon: "camera.fill", text: nil) {
          viewModel.capturePhoto()
        }
      }

      // Switch camera button (iPhone mode only)
      if viewModel.streamingMode == .iPhone {
        CircleButton(icon: "arrow.triangle.2.circlepath.camera", text: nil) {
          viewModel.switchIPhoneCamera()
        }
      }

      // Gemini AI button (disabled when WebRTC is active — audio conflict)
      CircleButton(
        icon: geminiVM.isGeminiActive ? "waveform.circle.fill" : "waveform.circle",
        text: "AI"
      ) {
        Task {
          if geminiVM.isGeminiActive {
            geminiVM.stopSession()
          } else {
            await geminiVM.startSession()
          }
        }
      }
      .opacity(webrtcVM.isActive ? 0.4 : 1.0)
      .disabled(webrtcVM.isActive)

      // WebRTC Live Stream button (disabled when Gemini is active — audio conflict)
      CircleButton(
        icon: webrtcVM.isActive
          ? "antenna.radiowaves.left.and.right.circle.fill"
          : "antenna.radiowaves.left.and.right.circle",
        text: "Live"
      ) {
        Task {
          if webrtcVM.isActive {
            webrtcVM.stopSession()
          } else {
            await webrtcVM.startSession()
          }
        }
      }
      .opacity(geminiVM.isGeminiActive ? 0.4 : 1.0)
      .disabled(geminiVM.isGeminiActive)
    }
  }
}
