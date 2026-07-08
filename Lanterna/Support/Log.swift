import Foundation
import OSLog

/// Centralized `os.Logger` instances for the app.
///
/// All logs go to the unified log store under the `pro.maule.Lanterna`
/// subsystem, split by category so you can filter in Console.app / `log stream`
/// with, e.g.:
///
///     log stream --predicate 'subsystem == "pro.maule.Lanterna" && category == "stream"'
///
/// Levels used across the app:
/// - `.debug`   — high-frequency / diagnostic; stripped from release by default
/// - `.info`    — expected lifecycle events
/// - `.notice`  — noteworthy state transitions worth keeping in prod
/// - `.error`   — recoverable failures
/// - `.fault`   — programmer errors / invariants that shouldn't happen
///
/// Interpolated values default to `<private>` on device. Wrap non-sensitive
/// values with `\(value, privacy: .public)` when you want them readable in
/// Console.app on release builds.
enum Log {
  private static let subsystem = "pro.maule.Lanterna"

  static let app          = Logger(subsystem: subsystem, category: "app")
  static let stream       = Logger(subsystem: subsystem, category: "stream")
  static let videoDecoder = Logger(subsystem: subsystem, category: "videoDecoder")
  static let iPhoneCamera = Logger(subsystem: subsystem, category: "iPhoneCamera")
  static let audio        = Logger(subsystem: subsystem, category: "audio")
  static let gemini       = Logger(subsystem: subsystem, category: "gemini")
  static let latency      = Logger(subsystem: subsystem, category: "latency")
  static let toolCall     = Logger(subsystem: subsystem, category: "toolCall")
  static let openClawWS   = Logger(subsystem: subsystem, category: "openClawWS")
  static let hermes       = Logger(subsystem: subsystem, category: "hermes")
  static let webRTC       = Logger(subsystem: subsystem, category: "webRTC")
  static let signaling    = Logger(subsystem: subsystem, category: "signaling")
  static let mockDevice   = Logger(subsystem: subsystem, category: "mockDevice")
}
