import Foundation
import WebRTC

protocol WebRTCClientDelegate: AnyObject {
  func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState)
  func webRTCClient(_ client: WebRTCClient, didGenerateCandidate candidate: RTCIceCandidate)
  func webRTCClient(_ client: WebRTCClient, didReceiveRemoteVideoTrack track: RTCVideoTrack)
  func webRTCClient(_ client: WebRTCClient, didRemoveRemoteVideoTrack track: RTCVideoTrack)
}

/// Manages RTCPeerConnection, video/audio tracks, and SDP negotiation.
/// Video uses a custom capturer (fed by DAT SDK frames). Audio uses WebRTC's native engine.
class WebRTCClient: NSObject {
  weak var delegate: WebRTCClientDelegate?

  private let factory: RTCPeerConnectionFactory
  private var peerConnection: RTCPeerConnection?
  private var videoSource: RTCVideoSource!
  private var videoCapturer: CustomVideoCapturer!
  private var localVideoTrack: RTCVideoTrack?
  private var localAudioTrack: RTCAudioTrack?
  private(set) var remoteVideoTrack: RTCVideoTrack?

  override init() {
    RTCInitializeSSL()
    let encoderFactory = RTCDefaultVideoEncoderFactory()
    let decoderFactory = RTCDefaultVideoDecoderFactory()
    self.factory = RTCPeerConnectionFactory(
      encoderFactory: encoderFactory,
      decoderFactory: decoderFactory
    )
    super.init()
  }

  func setup(iceServers: [RTCIceServer]? = nil) {
    let config = RTCConfiguration()
    config.iceServers = iceServers ?? [RTCIceServer(urlStrings: WebRTCConfig.stunServers)]
    config.sdpSemantics = .unifiedPlan
    config.continualGatheringPolicy = .gatherContinually

    let constraints = RTCMediaConstraints(
      mandatoryConstraints: nil,
      optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
    )

    peerConnection = factory.peerConnection(
      with: config, constraints: constraints, delegate: self
    )

    createMediaTracks()
  }

  private func createMediaTracks() {
    // Video track — custom source fed by DAT SDK frames
    videoSource = factory.videoSource()
    videoCapturer = CustomVideoCapturer(delegate: videoSource)
    localVideoTrack = factory.videoTrack(with: videoSource, trackId: "video0")
    localVideoTrack?.isEnabled = true
    peerConnection?.add(localVideoTrack!, streamIds: ["stream0"])

    // Audio track — WebRTC native audio (handles mic capture, AEC, playback)
    let audioConstraints = RTCMediaConstraints(
      mandatoryConstraints: nil, optionalConstraints: nil
    )
    let audioSource = factory.audioSource(with: audioConstraints)
    localAudioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
    localAudioTrack?.isEnabled = true
    peerConnection?.add(localAudioTrack!, streamIds: ["stream0"])
  }

  /// Called by ViewModel to push video frames from DAT SDK / iPhone camera.
  func pushVideoFrame(_ image: UIImage) {
    videoCapturer?.pushFrame(image)
  }

  // MARK: - SDP Negotiation

  func createOffer(completion: @escaping (RTCSessionDescription) -> Void) {
    let constraints = RTCMediaConstraints(
      mandatoryConstraints: [
        "OfferToReceiveAudio": "true",
        "OfferToReceiveVideo": "true",
      ],
      optionalConstraints: nil
    )
    peerConnection?.offer(for: constraints) { [weak self] sdp, error in
      guard let sdp else {
        Log.webRTC.error("Failed to create offer: \(error?.localizedDescription ?? "unknown", privacy: .public)")
        return
      }
      self?.peerConnection?.setLocalDescription(sdp) { error in
        if let error {
          Log.webRTC.error("Failed to set local description: \(error.localizedDescription, privacy: .public)")
        } else {
          completion(sdp)
        }
      }
    }
  }

  func set(remoteSdp: RTCSessionDescription, completion: @escaping (Error?) -> Void) {
    peerConnection?.setRemoteDescription(remoteSdp, completionHandler: completion)
  }

  func set(remoteCandidate: RTCIceCandidate, completion: @escaping (Error?) -> Void) {
    peerConnection?.add(remoteCandidate, completionHandler: completion)
  }

  func muteAudio(_ mute: Bool) {
    localAudioTrack?.isEnabled = !mute
  }

  func close() {
    localVideoTrack?.isEnabled = false
    localAudioTrack?.isEnabled = false
    remoteVideoTrack = nil
    peerConnection?.close()
    peerConnection = nil
    Log.webRTC.notice("Peer connection closed")
  }

  deinit {
    RTCCleanupSSL()
  }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCClient: RTCPeerConnectionDelegate {
  func peerConnection(
    _ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState
  ) {
    Log.webRTC.info("Signaling state: \(stateChanged.rawValue)")
  }

  func peerConnection(
    _ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState
  ) {
    Log.webRTC.info("ICE connection state: \(newState.rawValue)")
    delegate?.webRTCClient(self, didChangeConnectionState: newState)
  }

  func peerConnection(
    _ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState
  ) {
    Log.webRTC.info("ICE gathering state: \(newState.rawValue)")
  }

  func peerConnection(
    _ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate
  ) {
    // Log candidate type for debugging NAT traversal
    let sdp = candidate.sdp
    if sdp.contains("relay") {
      Log.webRTC.debug("ICE candidate: RELAY (TURN)")
    } else if sdp.contains("srflx") {
      Log.webRTC.debug("ICE candidate: SERVER REFLEXIVE (STUN)")
    } else if sdp.contains("host") {
      Log.webRTC.debug("ICE candidate: HOST (local)")
    }
    delegate?.webRTCClient(self, didGenerateCandidate: candidate)
  }

  func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
    Log.webRTC.info("Remote stream added with \(stream.audioTracks.count) audio tracks, \(stream.videoTracks.count) video tracks")
    if let videoTrack = stream.videoTracks.first {
      remoteVideoTrack = videoTrack
      delegate?.webRTCClient(self, didReceiveRemoteVideoTrack: videoTrack)
    }
  }

  func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
    Log.webRTC.info("Remote stream removed")
    if let track = remoteVideoTrack {
      remoteVideoTrack = nil
      delegate?.webRTCClient(self, didRemoveRemoteVideoTrack: track)
    }
  }

  func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
    Log.webRTC.debug("Negotiation needed")
  }

  func peerConnection(
    _ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]
  ) {}

  func peerConnection(
    _ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel
  ) {}
}
