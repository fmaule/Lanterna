import Foundation
import UIKit

@MainActor
class ToolCallRouter {
  private let bridge: HermesBridge
  private let currentFrameProvider: () -> UIImage?
  private var inFlightTasks: [String: Task<Void, Never>] = [:]
  private var consecutiveFailures = 0
  private let maxConsecutiveFailures = 3

  init(bridge: HermesBridge, currentFrameProvider: @escaping () -> UIImage? = { nil }) {
    self.bridge = bridge
    self.currentFrameProvider = currentFrameProvider
  }

  /// Route a tool call from Gemini to OpenClaw. Calls sendResponse with the
  /// JSON dictionary to send back as a toolResponse message.
  func handleToolCall(
    _ call: GeminiFunctionCall,
    sendResponse: @escaping ([String: Any]) -> Void
  ) {
    let callId = call.id
    let callName = call.name

    NSLog("[ToolCall] Received: %@ (id: %@) args: %@",
          callName, callId, String(describing: call.args))

    // Face-recognition tools are handled entirely on-device via
    // FaceRecognitionStore and never touch HermesBridge or the
    // Hermes-scoped circuit breaker below.
    if callName == "remember_face" || callName == "identify_face" {
      handleFaceToolCall(call, sendResponse: sendResponse)
      return
    }

    // Circuit breaker: stop sending tool calls after repeated failures
    if consecutiveFailures >= maxConsecutiveFailures {
      NSLog("[ToolCall] Circuit breaker open (%d consecutive failures), rejecting %@",
            consecutiveFailures, callId)
      let errorResult: ToolResult = .failure(
        "Tool execution is temporarily unavailable after \(consecutiveFailures) consecutive failures. " +
        "Please tell the user you cannot complete this action right now and suggest they check their Hermes connection."
      )
      let response = buildToolResponse(callId: callId, name: callName, result: errorResult)
      sendResponse(response)
      return
    }

    let task = Task { @MainActor in
      let taskDesc = call.args["task"] as? String ?? String(describing: call.args)
      let result = await bridge.delegateTask(task: taskDesc, toolName: callName)

      guard !Task.isCancelled else {
        NSLog("[ToolCall] Task %@ was cancelled, skipping response", callId)
        return
      }

      switch result {
      case .success:
        self.consecutiveFailures = 0
      case .failure:
        self.consecutiveFailures += 1
      }

      NSLog("[ToolCall] Result for %@ (id: %@): %@",
            callName, callId, String(describing: result))

      let response = self.buildToolResponse(callId: callId, name: callName, result: result)
      sendResponse(response)

      self.inFlightTasks.removeValue(forKey: callId)
    }

    inFlightTasks[callId] = task
  }

  /// Cancel specific in-flight tool calls (from toolCallCancellation)
  func cancelToolCalls(ids: [String]) {
    for id in ids {
      if let task = inFlightTasks[id] {
        NSLog("[ToolCall] Cancelling in-flight call: %@", id)
        task.cancel()
        inFlightTasks.removeValue(forKey: id)
      }
    }
    bridge.lastToolCallStatus = .cancelled(ids.first ?? "unknown")
  }

  /// Cancel all in-flight tool calls (on session stop)
  func cancelAll() {
    for (id, task) in inFlightTasks {
      NSLog("[ToolCall] Cancelling in-flight call: %@", id)
      task.cancel()
    }
    inFlightTasks.removeAll()
    consecutiveFailures = 0
  }

  // MARK: - Face recognition (on-device, never touches Hermes or consecutiveFailures)

  /// Handles `remember_face` / `identify_face` entirely on-device via
  /// `FaceRecognitionStore`. Deliberately does not read or write
  /// `consecutiveFailures` -- the Hermes circuit breaker must stay scoped to
  /// Hermes-routed calls only, so a face-tool failure (or a "no face found"
  /// outcome) must never trip or be blocked by it.
  private func handleFaceToolCall(
    _ call: GeminiFunctionCall,
    sendResponse: @escaping ([String: Any]) -> Void
  ) {
    let callId = call.id
    let callName = call.name

    let task = Task { @MainActor in
      let result = await self.resolveFaceToolResult(call)

      guard !Task.isCancelled else {
        NSLog("[ToolCall] Task %@ was cancelled, skipping response", callId)
        return
      }

      NSLog("[ToolCall] Result for %@ (id: %@): %@",
            callName, callId, String(describing: result))

      let response = self.buildToolResponse(callId: callId, name: callName, result: result)
      sendResponse(response)

      self.inFlightTasks.removeValue(forKey: callId)
    }

    inFlightTasks[callId] = task
  }

  private func resolveFaceToolResult(_ call: GeminiFunctionCall) async -> ToolResult {
    guard #available(iOS 18.0, *) else {
      return .success(
        "Face recognition isn't available on this version of iOS, so I couldn't complete that.")
    }

    guard let image = currentFrameProvider() else {
      return .success("I don't have a camera view to look at right now.")
    }

    switch call.name {
    case "remember_face":
      guard let name = call.args["name"] as? String, !name.isEmpty else {
        return .failure("The remember_face tool call is missing a required 'name' argument.")
      }
      do {
        try await FaceRecognitionStore.remember(name: name, image: image)
        return .success("Got it, I'll remember \(name).")
      } catch FaceRecognitionStore.FaceRecognitionStoreError.noFaceFound {
        return .success("I don't see a face right now, so I couldn't remember anyone.")
      } catch {
        return .failure("Failed to remember the face: \(error.localizedDescription)")
      }

    case "identify_face":
      do {
        guard let match = try await FaceRecognitionStore.identify(image: image) else {
          return .success("I don't recognize this person.")
        }
        return .success("This looks like \(match.name).")
      } catch {
        return .failure("Failed to identify the face: \(error.localizedDescription)")
      }

    default:
      // Unreachable: handleToolCall only routes these two names here.
      return .failure("Unknown face tool: \(call.name)")
    }
  }

  // MARK: - Private

  private func buildToolResponse(
    callId: String,
    name: String,
    result: ToolResult
  ) -> [String: Any] {
    return [
      "toolResponse": [
        "functionResponses": [
          [
            "id": callId,
            "name": name,
            "response": result.responseValue
          ]
        ]
      ]
    ]
  }
}
