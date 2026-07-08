import SwiftUI

/// Animated dark background: base linear gradient + three blurred radial-gradient
/// blobs that slowly drift via a `withAnimation(...repeatForever...)` loop, plus a
/// low-opacity Canvas noise pattern for depth. Adapted from OpenVision's
/// `AnimatedBackground` (the optional `ParticleEffect` is intentionally omitted
/// — it adds a `Timer` dependency for marginal visual gain).
struct AnimatedBackground: View {
  @State private var animate = false

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.02, green: 0.02, blue: 0.08),
          Color(red: 0.05, green: 0.02, blue: 0.12),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      GeometryReader { geometry in
        ZStack {
          Circle()
            .fill(
              RadialGradient(
                colors: [Color.blue.opacity(0.3), Color.blue.opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: geometry.size.width * 0.4
              )
            )
            .frame(width: geometry.size.width * 0.8)
            .offset(
              x: animate ? -geometry.size.width * 0.2 : geometry.size.width * 0.1,
              y: animate ? -geometry.size.height * 0.1 : geometry.size.height * 0.1
            )
            .blur(radius: 60)

          Circle()
            .fill(
              RadialGradient(
                colors: [Color.purple.opacity(0.25), Color.purple.opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: geometry.size.width * 0.5
              )
            )
            .frame(width: geometry.size.width)
            .offset(
              x: animate ? geometry.size.width * 0.2 : -geometry.size.width * 0.1,
              y: animate ? geometry.size.height * 0.3 : geometry.size.height * 0.2
            )
            .blur(radius: 80)

          Circle()
            .fill(
              RadialGradient(
                colors: [Color.cyan.opacity(0.15), Color.cyan.opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: geometry.size.width * 0.3
              )
            )
            .frame(width: geometry.size.width * 0.6)
            .offset(
              x: animate ? geometry.size.width * 0.3 : geometry.size.width * 0.1,
              y: animate ? -geometry.size.height * 0.2 : geometry.size.height * 0.3
            )
            .blur(radius: 50)
        }
      }

      Canvas { context, size in
        for _ in 0..<100 {
          let x = CGFloat.random(in: 0...size.width)
          let y = CGFloat.random(in: 0...size.height)
          let rect = CGRect(x: x, y: y, width: 1, height: 1)
          context.fill(Path(rect), with: .color(.white.opacity(0.03)))
        }
      }
      .allowsHitTesting(false)
    }
    .ignoresSafeArea()
    .onAppear {
      withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
        animate = true
      }
    }
  }
}

#Preview {
  ZStack {
    AnimatedBackground()
    Text("Lanterna")
      .font(.largeTitle.weight(.bold))
      .foregroundColor(.white)
  }
  .preferredColorScheme(.dark)
}
