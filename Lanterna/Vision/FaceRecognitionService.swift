import CoreML
import UIKit
import Vision

/// A stateless Vision-framework wrapper for on-device face detection and
/// feature-print ("embedding") generation and comparison.
///
/// Everything here runs entirely on-device: no network calls, no model
/// downloads. This type has no stored state — every operation is a pure
/// function of its inputs, so it's exposed as an uninstantiable enum
/// namespace rather than a class or struct instance.
///
/// This service intentionally does not decide what counts as a "match" —
/// `distance(between:and:)` reports a raw similarity distance from Vision's
/// feature-print embedding space (smaller means more similar), which is a
/// heuristic, not a calibrated probability or trained classifier. Choosing
/// a match/no-match threshold is a decision for the caller.
@available(iOS 18.0, *)
enum FaceRecognitionService {

  /// Outcome of attempting to locate a face in an image. "No face found" is
  /// a normal, expected outcome (e.g. a photo with no people in it), not an
  /// error condition.
  enum FaceDetectionResult {
    /// A face was found; the associated image is that face cropped from
    /// the source image. When multiple faces are present, this is always
    /// the one with the largest bounding-box area.
    case faceFound(CGImage)
    case noFaceFound
  }

  enum FaceRecognitionError: Error {
    /// The `UIImage` provided has no underlying `CGImage` to process.
    case invalidImage
    /// Archived feature-print `Data` could not be decoded back into a
    /// `FeaturePrintObservation` (corrupt or from an incompatible source).
    case invalidFeaturePrintData
  }

  // MARK: - Face detection

  /// Detects faces in `image` and returns the largest one, cropped, or
  /// `.noFaceFound` if none are present. Throws only for genuine Vision
  /// request failures, not for the "no face" case.
  static func detectLargestFace(in image: UIImage) throws -> FaceDetectionResult {
    guard let cgImage = image.cgImage else {
      throw FaceRecognitionError.invalidImage
    }
    return try detectLargestFace(in: cgImage)
  }

  /// Detects faces in `cgImage` and returns the largest one, cropped, or
  /// `.noFaceFound` if none are present. When several faces are detected,
  /// "largest" is decided here (by normalized bounding-box area) so callers
  /// never need to implement that policy themselves.
  static func detectLargestFace(in cgImage: CGImage) throws -> FaceDetectionResult {
    let handler = VNImageRequestHandler(cgImage: cgImage)
    let request = VNDetectFaceRectanglesRequest()
    #if targetEnvironment(simulator)
      // iOS Simulator's CoreML backend fails to load the default (newer,
      // revision 3) face-rectangles model with "Could not create inference
      // context." Pinning to revision 2 avoids that Simulator-only crash.
      // Real devices don't hit this and use Vision's current default
      // revision.
      request.revision = VNDetectFaceRectanglesRequestRevision2
    #endif
    try handler.perform([request])
    let observations = request.results as? [VNFaceObservation] ?? []

    let largest = observations.max { lhs, rhs in
      let lhsArea = lhs.boundingBox.width * lhs.boundingBox.height
      let rhsArea = rhs.boundingBox.width * rhs.boundingBox.height
      return lhsArea < rhsArea
    }

    guard let largest else {
      return .noFaceFound
    }

    // boundingBox is normalized with a bottom-left origin; VNImageRectForNormalizedRect
    // converts it to top-left-origin pixel coordinates for CGImage cropping.
    let pixelRect = VNImageRectForNormalizedRect(largest.boundingBox, cgImage.width, cgImage.height)
    guard let croppedCGImage = cgImage.cropping(to: pixelRect) else {
      return .noFaceFound
    }
    return .faceFound(croppedCGImage)
  }

  // MARK: - Feature prints (embeddings)

  /// Generates a feature-print "embedding" for `faceImage` (expected to
  /// already be a cropped face, e.g. from `detectLargestFace`) and returns
  /// it archived as `Data` suitable for persistence. Genuinely throws on
  /// Vision request failure.
  static func generateFeaturePrintData(for faceImage: CGImage) async throws -> Data {
    var request = GenerateImageFeaturePrintRequest()
    #if targetEnvironment(simulator)
      // iOS Simulator's CoreML backend fails to load this model's default
      // (Neural Engine / GPU) compute path with "Failed to create espresso
      // context." Forcing CPU avoids the crash so the pipeline is testable
      // in Simulator, but the CPU fallback has been observed (on this SDK)
      // to return effectively-constant embeddings that don't discriminate
      // between different faces — i.e. Simulator results are not
      // representative of real similarity. Real devices hit neither
      // problem and don't take this branch.
      if let cpuDevice = MLComputeDevice.allComputeDevices.first(where: {
        if case .cpu = $0 { return true }
        return false
      }) {
        request.setComputeDevice(cpuDevice, for: .main)
      }
    #endif
    let featurePrint = try await request.perform(on: faceImage)
    return try PropertyListEncoder().encode(featurePrint)
  }

  /// Compares two archived feature prints (as produced by
  /// `generateFeaturePrintData(for:)`) and returns their distance. Smaller
  /// values mean more similar faces; this is an unbounded similarity
  /// heuristic from Vision's embedding space, not a probability — callers
  /// pick their own match threshold.
  static func distance(between lhsData: Data, and rhsData: Data) throws -> Float {
    let decoder = PropertyListDecoder()
    guard let lhs = try? decoder.decode(FeaturePrintObservation.self, from: lhsData) else {
      throw FaceRecognitionError.invalidFeaturePrintData
    }
    guard let rhs = try? decoder.decode(FeaturePrintObservation.self, from: rhsData) else {
      throw FaceRecognitionError.invalidFeaturePrintData
    }
    return Float(try lhs.distance(to: rhs))
  }
}
