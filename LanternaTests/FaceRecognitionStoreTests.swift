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
final class FaceRecognitionStoreTests: XCTestCase {

  private var tempDirectory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    // Each test gets its own fresh, isolated storage directory so tests
    // never share on-disk state or interfere with each other.
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("FaceRecognitionStoreTests-\(UUID().uuidString)", isDirectory: true)
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

  // MARK: - remember + identify round trip

  func testRememberThenIdentify_sameImage_identifiesWithSmallDistance() async throws {
    let image = try loadImage(named: "face1", withExtension: "jpg")

    try await FaceRecognitionStore.remember(name: "Alice", image: image)
    let result = try await FaceRecognitionStore.identify(image: image)

    guard let result else {
      XCTFail("Expected identify to find a match for the just-remembered face")
      return
    }
    XCTAssertEqual(result.name, "Alice")
    XCTAssertLessThan(
      result.distance, 0.1,
      "Re-identifying the exact same image should yield a very small distance")
  }

  func testRememberAliceAsFace1_identifyWithFace2_noMatch() async throws {
    #if targetEnvironment(simulator)
      // See FaceRecognitionService.generateFeaturePrintData's
      // #if targetEnvironment(simulator) comment: on iOS Simulator, the CPU
      // fallback used to dodge a Simulator-only CoreML crash has been
      // observed to return near-constant embeddings that don't
      // discriminate between different faces. That makes this assertion --
      // which depends on real discrimination between face1 and face2 --
      // unverifiable here. Confirmed real device behavior is expected to
      // differ; skip here rather than assert on data known to be
      // meaningless in this environment.
      throw XCTSkip("Feature-print discrimination is not verifiable on iOS Simulator; see comment.")
    #endif
    let face1Image = try loadImage(named: "face1", withExtension: "jpg")
    let face2Image = try loadImage(named: "face2", withExtension: "jpg")

    try await FaceRecognitionStore.remember(name: "Alice", image: face1Image)
    let result = try await FaceRecognitionStore.identify(image: face2Image)

    XCTAssertNil(result, "face2 is a different face from the remembered Alice (face1); expected no match")
  }

  // MARK: - identify: no-match / no-throw cases

  func testIdentify_noKnownFaces_returnsNil() async throws {
    let image = try loadImage(named: "face1", withExtension: "jpg")

    let result = try await FaceRecognitionStore.identify(image: image)

    XCTAssertNil(result)
  }

  func testIdentify_imageWithNoFace_returnsNil() async throws {
    let plantImage = try loadImage(named: "plant", withExtension: "png")
    let faceImage = try loadImage(named: "face1", withExtension: "jpg")
    try await FaceRecognitionStore.remember(name: "Alice", image: faceImage)

    let result = try await FaceRecognitionStore.identify(image: plantImage)

    XCTAssertNil(result, "An image with no detectable face should yield nil, not a thrown error")
  }

  // MARK: - remember: no-face case

  func testRemember_imageWithNoFace_throwsNoFaceFound() async throws {
    let plantImage = try loadImage(named: "plant", withExtension: "png")

    do {
      try await FaceRecognitionStore.remember(name: "Plant", image: plantImage)
      XCTFail("Expected remember(name:image:) to throw for an image with no detectable face")
    } catch FaceRecognitionStore.FaceRecognitionStoreError.noFaceFound {
      // Expected.
    }
  }

  // MARK: - allNames / forget

  func testAllNamesAndForget_reflectRememberedAndForgottenState() async throws {
    let face1Image = try loadImage(named: "face1", withExtension: "jpg")
    let face2Image = try loadImage(named: "face2", withExtension: "jpg")

    try await FaceRecognitionStore.remember(name: "Alice", image: face1Image)
    try await FaceRecognitionStore.remember(name: "Bob", image: face2Image)

    XCTAssertEqual(FaceRecognitionStore.allNames(), ["Alice", "Bob"])

    FaceRecognitionStore.forget(name: "Alice")

    XCTAssertEqual(FaceRecognitionStore.allNames(), ["Bob"])
    let result = try await FaceRecognitionStore.identify(image: face1Image)
    XCTAssertNotEqual(
      result?.name, "Alice",
      "Alice was forgotten; identify should no longer be able to report her as a match")
  }

  func testForget_nameNeverStored_isNoOp() {
    // Should not throw and should not affect the (empty) stored state.
    FaceRecognitionStore.forget(name: "NeverRemembered")

    XCTAssertEqual(FaceRecognitionStore.allNames(), [])
  }

  // MARK: - remember overwrites existing entry

  func testRemember_sameNameTwice_overwritesRatherThanDuplicates() async throws {
    let face1Image = try loadImage(named: "face1", withExtension: "jpg")
    let face2Image = try loadImage(named: "face2", withExtension: "jpg")

    try await FaceRecognitionStore.remember(name: "Alice", image: face1Image)
    try await FaceRecognitionStore.remember(name: "Alice", image: face2Image)

    XCTAssertEqual(FaceRecognitionStore.allNames(), ["Alice"])
  }
}
