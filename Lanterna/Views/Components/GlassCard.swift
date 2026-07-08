import SwiftUI

/// Glassmorphic card: `.ultraThinMaterial` blur, subtle white gradient overlay,
/// and a soft border stroke. Adapted from OpenVision's `GlassCard`.
struct GlassCard<Content: View>: View {
  private let content: Content
  private let cornerRadius: CGFloat
  private let opacity: CGFloat

  init(
    cornerRadius: CGFloat = 20,
    opacity: CGFloat = 0.15,
    @ViewBuilder content: () -> Content
  ) {
    self.cornerRadius = cornerRadius
    self.opacity = opacity
    self.content = content()
  }

  var body: some View {
    content
      .background(
        ZStack {
          RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.ultraThinMaterial)

          RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
              LinearGradient(
                colors: [
                  Color.white.opacity(opacity),
                  Color.white.opacity(opacity * 0.3),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )

          RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(
              LinearGradient(
                colors: [
                  Color.white.opacity(0.3),
                  Color.white.opacity(0.1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              ),
              lineWidth: 1
            )
        }
      )
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
  }
}

#Preview {
  ZStack {
    AnimatedBackground()
    GlassCard {
      VStack(spacing: 8) {
        Text("Glass Card")
          .font(.headline)
          .foregroundColor(.white)
        Text("frosted material + gradient overlay")
          .font(.subheadline)
          .foregroundColor(.white.opacity(0.7))
      }
      .padding(24)
    }
    .padding(32)
  }
  .preferredColorScheme(.dark)
}
