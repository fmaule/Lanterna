import SwiftUI

/// Compact capsule pill with a status dot and label, rendered on top of a
/// `.ultraThinMaterial` background with a soft white stroke. When `isConnected`
/// is true, the dot gets a subtle pulsing halo. Adapted from OpenVision.
///
/// The `(color:text:)` initializer preserves the call-site API of Lanterna's
/// previous `StatusPill` (used in the Gemini / OpenClaw / WebRTC status bars)
/// and derives `isConnected` from the color — green ⇒ live/connected.
struct StatusPill: View {
  let text: String
  let color: Color
  let isConnected: Bool

  init(color: Color, text: String, isConnected: Bool? = nil) {
    self.color = color
    self.text = text
    self.isConnected = isConnected ?? (color == .green)
  }

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)
        .overlay(
          Circle()
            .stroke(color.opacity(0.5), lineWidth: 2)
            .scaleEffect(isConnected ? 1.5 : 1)
            .opacity(isConnected ? 0 : 1)
            .animation(
              isConnected
                ? .easeOut(duration: 1).repeatForever(autoreverses: false)
                : .default,
              value: isConnected
            )
        )

      Text(text)
        .font(.caption)
        .fontWeight(.medium)
    }
    .foregroundColor(.white.opacity(0.9))
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(
      Capsule()
        .fill(.ultraThinMaterial)
        .overlay(
          Capsule()
            .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    )
  }
}

#Preview {
  ZStack {
    AnimatedBackground()
    VStack(spacing: 12) {
      StatusPill(color: .green, text: "Gemini")
      StatusPill(color: .yellow, text: "Connecting…")
      StatusPill(color: .red, text: "Error")
      StatusPill(color: .gray, text: "Off")
    }
  }
  .preferredColorScheme(.dark)
}
