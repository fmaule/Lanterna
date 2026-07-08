import AudioToolbox
import Foundation
import UIKit

/// Non-visual cues (haptics + short system sounds) for tool-call state
/// transitions. The primary user of this app is blind, so the "Working on
/// it…" pill in the overlay isn't enough on its own — we need something the
/// wrist and ear can pick up.
///
/// Haptics carry most of the signal (they don't fight with the assistant's
/// spoken output or the active `.playAndRecord` session). The system sounds
/// are supplementary; if a given `SystemSoundID` isn't installed on the
/// current OS build, `AudioServicesPlaySystemSound` silently no-ops which is
/// fine.
@MainActor
final class ToolCallFeedback {
  static let shared = ToolCallFeedback()

  // Feedback generators are cheap but Apple recommends reusing them so the
  // Taptic Engine stays warm between calls.
  private let notificationHaptic = UINotificationFeedbackGenerator()
  private let softImpact = UIImpactFeedbackGenerator(style: .soft)
  private let lightImpact = UIImpactFeedbackGenerator(style: .light)

  private init() {}

  /// Emit feedback for the transition `old -> new`. Safe to call from a
  /// polling loop — nothing fires when the two states are equal.
  func handleTransition(from old: ToolCallStatus, to new: ToolCallStatus) {
    guard old != new else { return }
    guard SettingsManager.shared.toolCallSoundsEnabled else { return }

    switch new {
    case .idle:
      break

    case .executing:
      lightImpact.prepare()
      lightImpact.impactOccurred()
      // begin_record.caf — short low bloop; reads as "starting".
      AudioServicesPlaySystemSound(SystemSoundID(1113))

    case .completed:
      notificationHaptic.prepare()
      notificationHaptic.notificationOccurred(.success)
      // end_record.caf — short high bloop; natural counterpart to 1113.
      AudioServicesPlaySystemSound(SystemSoundID(1114))

    case .failed:
      notificationHaptic.prepare()
      notificationHaptic.notificationOccurred(.error)
      // sms-received5 style short alert; if unavailable it just no-ops and
      // the error haptic still carries the signal.
      AudioServicesPlaySystemSound(SystemSoundID(1073))

    case .cancelled:
      softImpact.prepare()
      softImpact.impactOccurred()
    }
  }
}
