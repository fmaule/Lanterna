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

@MainActor
final class GeminiSessionViewModelTests: XCTestCase {

  private var originalVideoStreamingEnabled: Bool!

  override func setUpWithError() throws {
    try super.setUpWithError()
    // `videoStreamingEnabled` is a real shared singleton backed by
    // UserDefaults -- save it so we can restore it and never leak state
    // into other tests.
    originalVideoStreamingEnabled = SettingsManager.shared.videoStreamingEnabled
  }

  override func tearDownWithError() throws {
    SettingsManager.shared.videoStreamingEnabled = originalVideoStreamingEnabled
    try super.tearDownWithError()
  }

  private func makeTestImage(color: UIColor) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
    return renderer.image { context in
      color.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
    }
  }

  // MARK: - Caching happens even when transmission to Gemini would be skipped

  func testSendVideoFrameIfThrottled_cachesFrame_evenWhenVideoStreamingDisabled() {
    SettingsManager.shared.videoStreamingEnabled = false

    let viewModel = GeminiSessionViewModel()
    let image = makeTestImage(color: .red)

    viewModel.sendVideoFrameIfThrottled(image: image)

    XCTAssertNotNil(
      viewModel.latestFrame,
      "latestFrame should be cached unconditionally, even when videoStreamingEnabled is false")
    XCTAssertTrue(
      viewModel.latestFrame === image,
      "latestFrame should be reference-identical to the image that was passed in")
  }

  func testSendVideoFrameIfThrottled_updatesLatestFrame_onEachCall() {
    SettingsManager.shared.videoStreamingEnabled = false

    let viewModel = GeminiSessionViewModel()
    let firstImage = makeTestImage(color: .red)
    let secondImage = makeTestImage(color: .blue)

    viewModel.sendVideoFrameIfThrottled(image: firstImage)
    XCTAssertTrue(viewModel.latestFrame === firstImage)

    viewModel.sendVideoFrameIfThrottled(image: secondImage)
    XCTAssertTrue(
      viewModel.latestFrame === secondImage,
      "A second call with a different image should update latestFrame, not only capture the first frame ever")
  }
}
