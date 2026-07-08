/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import UIKit
import XCTest

@testable import Lanterna

/// Thrown by test helpers after an `XCTFail` purely to unwind the current
/// test early. Never use `XCTSkip` for these -- these guards represent
/// genuine regressions (e.g. a fixture went missing), which must show up
/// as a **failed** test in CI, not a **skipped** one.
private struct TestSetupFailure: Error {}

@available(iOS 18.0, *)
@MainActor
final class ToolCallRouterTests: XCTestCase {

  private var tempDirectory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    // Each test gets its own fresh, isolated storage directory so tests
    // never share on-disk state with each other or with
    // FaceRecognitionStoreTests.
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ToolCallRouterTests-\(UUID().uuidString)", isDirectory: true)
    FaceRecognitionStore.resetForTesting(storageDirectory: tempDirectory)
  }

  override func tearDownWithError() throws {
    FaceRecognitionStore.resetForTesting()
    if let tempDirectory {
      try? FileManager.default.removeItem(at: tempDirectory)
    }
    try super.tearDownWithError()
  }

  private func loadImage(named name: String, withExtension ext: String) throws -> UIImage {
    guard let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: ext) else {
      XCTFail("Could not find resource \(name).\(ext) in test bundle")
      throw TestSetupFailure()
    }
    guard let image = UIImage(contentsOfFile: url.path) else {
      XCTFail("Could not load UIImage from \(url)")
      throw TestSetupFailure()
    }
    return image
  }

  /// Calls `handleToolCall` and awaits (with a bounded poll loop) the single
  /// response dictionary passed to `sendResponse`.
  private func awaitResponse(
    router: ToolCallRouter,
    call: GeminiFunctionCall
  ) async throws -> [String: Any] {
    final class Box: @unchecked Sendable {
      var response: [String: Any]?
    }
    let box = Box()

    router.handleToolCall(call) { response in
      box.response = response
    }

    // Poll briefly for the async Task inside handleToolCall to complete.
    for _ in 0..<200 {
      if box.response != nil {
        break
      }
      try await Task.sleep(nanoseconds: 50_000_000)
    }

    guard let response = box.response else {
      XCTFail("sendResponse was never called for \(call.name)")
      throw TestSetupFailure()
    }
    return response
  }

  /// Extracts the `result`/`error` string out of a
  /// toolResponse/functionResponses/response payload, plus whether it was
  /// framed as a success or a failure.
  private func extractResult(_ response: [String: Any]) throws -> (isSuccess: Bool, text: String) {
    guard
      let toolResponse = response["toolResponse"] as? [String: Any],
      let functionResponses = toolResponse["functionResponses"] as? [[String: Any]],
      let first = functionResponses.first,
      let result = first["response"] as? [String: Any]
    else {
      XCTFail("Response was not shaped like a toolResponse/functionResponses payload: \(response)")
      throw TestSetupFailure()
    }

    if let success = result["result"] as? String {
      return (true, success)
    }
    if let failure = result["error"] as? String {
      return (false, failure)
    }
    XCTFail("Response's result dictionary had neither 'result' nor 'error': \(result)")
    throw TestSetupFailure()
  }

  // MARK: - remember_face / identify_face round trip

  func testRememberFace_thenIdentifyFace_identifiesTheRememberedName() async throws {
    let faceImage = try loadImage(named: "face1", withExtension: "jpg")
    let router = ToolCallRouter(bridge: HermesBridge(), currentFrameProvider: { faceImage })

    let rememberCall = GeminiFunctionCall(
      id: "call-1", name: "remember_face", args: ["name": "Alice"])
    let rememberResponse = try await awaitResponse(router: router, call: rememberCall)
    let rememberResult = try extractResult(rememberResponse)

    XCTAssertTrue(rememberResult.isSuccess, "remember_face on a real face should succeed")
    XCTAssertTrue(
      rememberResult.text.contains("Alice"),
      "remember_face's response should mention the remembered name: \(rememberResult.text)")

    let identifyCall = GeminiFunctionCall(id: "call-2", name: "identify_face", args: [:])
    let identifyResponse = try await awaitResponse(router: router, call: identifyCall)
    let identifyResult = try extractResult(identifyResponse)

    XCTAssertTrue(identifyResult.isSuccess, "identify_face should succeed")
    XCTAssertTrue(
      identifyResult.text.contains("Alice"),
      "identify_face's response should mention the identified name: \(identifyResult.text)")
  }

  // MARK: - remember_face: no face in frame is "nothing to report", not a failure

  func testRememberFace_noFaceInFrame_isSuccessNotFailure() async throws {
    let plantImage = try loadImage(named: "plant", withExtension: "png")
    let router = ToolCallRouter(bridge: HermesBridge(), currentFrameProvider: { plantImage })

    let call = GeminiFunctionCall(id: "call-3", name: "remember_face", args: ["name": "Nobody"])
    let response = try await awaitResponse(router: router, call: call)
    let result = try extractResult(response)

    XCTAssertTrue(
      result.isSuccess,
      "No face found should be framed as a success 'nothing to report' outcome, not a failure")
    XCTAssertTrue(
      result.text.lowercased().contains("face"),
      "The no-face response should explain that no face was found: \(result.text)")
  }

  // MARK: - remember_face: missing/empty name argument is a genuine error

  func testRememberFace_missingNameArgument_isFailure() async throws {
    let faceImage = try loadImage(named: "face1", withExtension: "jpg")
    let router = ToolCallRouter(bridge: HermesBridge(), currentFrameProvider: { faceImage })

    let call = GeminiFunctionCall(id: "call-4", name: "remember_face", args: [:])
    let response = try await awaitResponse(router: router, call: call)
    let result = try extractResult(response)

    XCTAssertFalse(
      result.isSuccess,
      "A missing 'name' argument is a genuine tool-call malformation and should be a failure")
  }

  func testRememberFace_emptyNameArgument_isFailure() async throws {
    let faceImage = try loadImage(named: "face1", withExtension: "jpg")
    let router = ToolCallRouter(bridge: HermesBridge(), currentFrameProvider: { faceImage })

    let call = GeminiFunctionCall(id: "call-5", name: "remember_face", args: ["name": ""])
    let response = try await awaitResponse(router: router, call: call)
    let result = try extractResult(response)

    XCTAssertFalse(result.isSuccess, "An empty 'name' argument should be a failure")
  }

  // MARK: - identify_face: no known faces is "nothing to report", not a failure

  func testIdentifyFace_noKnownFaces_isSuccessNotFailure() async throws {
    let faceImage = try loadImage(named: "face1", withExtension: "jpg")
    let router = ToolCallRouter(bridge: HermesBridge(), currentFrameProvider: { faceImage })

    let call = GeminiFunctionCall(id: "call-6", name: "identify_face", args: [:])
    let response = try await awaitResponse(router: router, call: call)
    let result = try extractResult(response)

    XCTAssertTrue(
      result.isSuccess,
      "No known faces should be framed as a success 'nothing to report' outcome, not a failure")
  }

  // MARK: - identify_face: no camera frame available is "nothing to report", not a failure

  func testIdentifyFace_noCameraFrame_isSuccessNotFailure() async throws {
    let router = ToolCallRouter(bridge: HermesBridge(), currentFrameProvider: { nil })

    let call = GeminiFunctionCall(id: "call-7", name: "identify_face", args: [:])
    let response = try await awaitResponse(router: router, call: call)
    let result = try extractResult(response)

    XCTAssertTrue(
      result.isSuccess,
      "No camera frame available should be a success 'nothing to report' outcome, not a failure")
  }
}
