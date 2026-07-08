/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import UIKit

/// Persistence and the "is this a known face" decision, built on top of
/// `FaceRecognitionService`'s stateless Vision wrapper.
///
/// `FaceRecognitionService.distance` is deliberately just a raw similarity
/// measurement with no opinion about what counts as a match — this type
/// owns that decision (see `matchThreshold` below), plus the on-disk
/// storage of remembered name -> feature-print mappings.
///
/// Like `FaceRecognitionService`, this is exposed as an uninstantiable enum
/// namespace with `static var` state rather than a class instance or actor.
/// Callers (`ToolCallRouter`, `GeminiSessionViewModel`, per Task 4/6) are
/// already `@MainActor`-confined, matching the non-actor, singleton-ish
/// pattern `SettingsManager` uses elsewhere in this codebase — this file
/// does not introduce new concurrency machinery.
@available(iOS 18.0, *)
enum FaceRecognitionStore {

  enum FaceRecognitionStoreError: Error {
    /// No face was detected in the image passed to remember(name:image:).
    /// Not used for identify(image:) — see its doc comment.
    case noFaceFound
  }

  /// One remembered person: a display name plus their archived feature
  /// print (as produced by `FaceRecognitionService.generateFeaturePrintData`).
  /// This is a separate, simpler struct of our own -- not an archive of
  /// `FeaturePrintObservation` itself -- persisted as a plist.
  private struct KnownFace: Codable {
    let name: String
    let featurePrintData: Data
  }

  /// Distances below this count as the same person. This is an empirical
  /// heuristic over Vision's feature-print embedding space, not a
  /// calibrated probability or trained classifier -- tune if false
  /// positives/negatives show up in real use.
  private static let matchThreshold: Float = 0.6

  private static let storageFileName = "known-faces.plist"

  /// The directory known-faces.plist lives in. Overridable so tests can
  /// point the store at an isolated temporary directory instead of the
  /// real Application Support location; production callers never need to
  /// touch this.
  static var storageDirectoryURL: URL = defaultStorageDirectoryURL

  private static var defaultStorageDirectoryURL: URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return appSupport.appendingPathComponent("FaceRecognition", isDirectory: true)
  }

  private static var storageFileURL: URL {
    storageDirectoryURL.appendingPathComponent(storageFileName)
  }

  /// In-memory cache of the loaded array: load once, mutate + persist on
  /// remember/forget, rather than re-reading the file on every call.
  private static var cache: [KnownFace]?

  /// Test-only hook: points the store at a fresh storage directory (or, if
  /// `nil`, back at the real default) and clears the in-memory cache so a
  /// previous test's state can't leak into the next one. Not part of the
  /// API Task 4/6 depend on.
  static func resetForTesting(storageDirectory: URL? = nil) {
    storageDirectoryURL = storageDirectory ?? defaultStorageDirectoryURL
    cache = nil
  }

  // MARK: - Loading / persisting

  private static func loadFaces() -> [KnownFace] {
    if let cache {
      return cache
    }
    let loaded: [KnownFace]
    if let data = try? Data(contentsOf: storageFileURL),
      let decoded = try? PropertyListDecoder().decode([KnownFace].self, from: data)
    {
      loaded = decoded
    } else {
      // Missing file on first launch (or an unreadable/corrupt one) = zero
      // known faces, not an error.
      loaded = []
    }
    cache = loaded
    return loaded
  }

  private static func persist(_ faces: [KnownFace]) throws {
    try FileManager.default.createDirectory(
      at: storageDirectoryURL, withIntermediateDirectories: true)
    let data = try PropertyListEncoder().encode(faces)
    try data.write(to: storageFileURL, options: .atomic)
    cache = faces
  }

  // MARK: - Public API

  /// Detects the face in `image`, archives its feature print, and saves it
  /// under `name`. Overwrites any existing entry with the same `name`.
  /// Throws `FaceRecognitionStoreError.noFaceFound` if no face is detected
  /// in `image` (a normal, expected outcome the caller should present as
  /// "I don't see a face right now", not as an internal error) -- throws
  /// other errors only for genuine Vision/I-O failures.
  static func remember(name: String, image: UIImage) async throws {
    let detection = try FaceRecognitionService.detectLargestFace(in: image)
    guard case .faceFound(let faceImage) = detection else {
      throw FaceRecognitionStoreError.noFaceFound
    }
    let featurePrintData = try await FaceRecognitionService.generateFeaturePrintData(for: faceImage)

    var faces = loadFaces()
    faces.removeAll { $0.name == name }
    faces.append(KnownFace(name: name, featurePrintData: featurePrintData))
    try persist(faces)
  }

  /// Detects the face in `image` and compares it against every stored
  /// print. Returns the closest match if it's within the match threshold,
  /// else `nil`. `nil` uniformly covers: no face detected in `image`, zero
  /// known faces stored, and "closest known face is too far to count as a
  /// match" -- all three are the same "nothing to report" outcome to the
  /// caller, so this does NOT throw for any of them. It still throws for
  /// genuine Vision/I-O failures (e.g. a corrupted stored print).
  static func identify(image: UIImage) async throws -> (name: String, distance: Float)? {
    let detection = try FaceRecognitionService.detectLargestFace(in: image)
    guard case .faceFound(let faceImage) = detection else {
      return nil
    }

    let faces = loadFaces()
    guard !faces.isEmpty else {
      return nil
    }

    let queryData = try await FaceRecognitionService.generateFeaturePrintData(for: faceImage)

    var best: (name: String, distance: Float)?
    for face in faces {
      let distance = try FaceRecognitionService.distance(between: queryData, and: face.featurePrintData)
      if best == nil || distance < best!.distance {
        best = (face.name, distance)
      }
    }

    guard let best, best.distance < matchThreshold else {
      return nil
    }
    return best
  }

  /// All currently-remembered names, in the order they should display in
  /// Settings. Order chosen: insertion order (the order names were first
  /// remembered in), matching the order they're stored in the underlying
  /// array.
  static func allNames() -> [String] {
    loadFaces().map(\.name)
  }

  /// Removes the stored entry for `name`, if any. No-op (not an error) if
  /// `name` isn't currently stored.
  static func forget(name: String) {
    var faces = loadFaces()
    guard faces.contains(where: { $0.name == name }) else {
      return
    }
    faces.removeAll { $0.name == name }
    try? persist(faces)
  }
}
