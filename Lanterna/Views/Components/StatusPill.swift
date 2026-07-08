import SwiftUI

/// Compact capsule pill with a solid status dot and label on a dark translucent
/// background. Preserves the pre-refresh visual — no pulsing halo, no
/// glassmorphic material — which reads better than the OpenVision variant when
/// several pills are stacked on the live camera feed.
struct StatusPill: View {
  let text: String
  let color: Color

  init(color: Color, text: String) {
    self.color = color
    self.text = text
  }

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)
      Text(text)
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.white)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Color.black.opacity(0.6))
    .cornerRadius(16)
  }
}

#Preview {
  ZStack {
    Color.gray.ignoresSafeArea()
    VStack(spacing: 12) {
      StatusPill(color: .green, text: "Gemini")
      StatusPill(color: .yellow, text: "Connecting…")
      StatusPill(color: .red, text: "Error")
      StatusPill(color: .gray, text: "Off")
    }
  }
}
