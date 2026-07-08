import SwiftUI

/// `Canvas`-drawn sine wave with an animated phase and a blue→purple→blue
/// gradient stroke. When `isActive` is true the amplitude reflects `intensity`
/// (0…1); otherwise a low idle amplitude is drawn. Adapted from OpenVision.
///
/// Lanterna doesn't currently expose live audio amplitude from `AudioManager`,
/// so callers typically pass a fixed intensity when the model is speaking.
struct WaveformVisualizer: View {
  let isActive: Bool
  let intensity: CGFloat

  @State private var phase: CGFloat = 0

  init(isActive: Bool, intensity: CGFloat = 0.6) {
    self.isActive = isActive
    self.intensity = intensity
  }

  var body: some View {
    Canvas { context, size in
      let midY = size.height / 2
      let amplitude = isActive ? (size.height / 3) * intensity : size.height / 8

      var path = Path()
      path.move(to: CGPoint(x: 0, y: midY))

      for x in stride(from: 0, through: size.width, by: 2) {
        let relativeX = x / size.width
        let sine = sin((relativeX * 4 * .pi) + phase)
        let y = midY + (sine * amplitude)
        path.addLine(to: CGPoint(x: x, y: y))
      }

      context.stroke(
        path,
        with: .linearGradient(
          Gradient(colors: [
            Color.blue.opacity(0.8),
            Color.purple.opacity(0.8),
            Color.blue.opacity(0.8),
          ]),
          startPoint: CGPoint(x: 0, y: midY),
          endPoint: CGPoint(x: size.width, y: midY)
        ),
        lineWidth: 3
      )
    }
    .onAppear { startAnimation() }
    .onChange(of: isActive) { _, _ in startAnimation() }
  }

  private func startAnimation() {
    guard isActive else { return }
    withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
      phase = 2 * .pi
    }
  }
}

#Preview {
  ZStack {
    AnimatedBackground()
    WaveformVisualizer(isActive: true, intensity: 0.8)
      .frame(height: 60)
      .padding()
  }
  .preferredColorScheme(.dark)
}
