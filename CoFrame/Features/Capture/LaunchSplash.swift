import SwiftUI

/// Launch splash shown while the camera session is bootstrapping.
/// Mirrors the app icon (two overlapping frames + record dot on a deep blue
/// gradient), then "blooms" each element in sequence. The dot keeps pulsing
/// while we wait, so users always see something alive.
struct LaunchSplash: View {
    private let frameSize: CGFloat = 240
    private let dotSize: CGFloat = 36

    @State private var landScale: CGFloat = 0.5
    @State private var landOpacity: Double = 0
    @State private var portScale: CGFloat = 0.5
    @State private var portOpacity: Double = 0
    @State private var dotScale: CGFloat = 0
    @State private var dotPulse: CGFloat = 1.0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.20, green: 0.36, blue: 0.55),
                    Color(red: 0.06, green: 0.10, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    // 16:9 landscape frame
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.42, green: 0.70, blue: 0.98).opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.95), lineWidth: 5)
                        )
                        .frame(width: frameSize, height: frameSize * 9.0 / 16.0)
                        .scaleEffect(landScale)
                        .opacity(landOpacity)

                    // 9:16 portrait frame, drawn on top so the overlap reads correctly
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.98, green: 0.70, blue: 0.42).opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.95), lineWidth: 5)
                        )
                        .frame(width: frameSize * 9.0 / 16.0, height: frameSize)
                        .scaleEffect(portScale)
                        .opacity(portOpacity)

                    // Record dot with a soft halo
                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: dotSize + 18, height: dotSize + 18)
                        .scaleEffect(dotScale)

                    Circle()
                        .fill(Color(red: 0.95, green: 0.22, blue: 0.22))
                        .frame(width: dotSize, height: dotSize)
                        .scaleEffect(dotScale * dotPulse)
                        .shadow(color: Color(red: 0.95, green: 0.22, blue: 0.22).opacity(0.5),
                                radius: 8)
                }
                .frame(height: frameSize)

                Text("CoFrame")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.7))
                    .opacity(landOpacity)
            }
        }
        .onAppear { animateIn() }
    }

    private func animateIn() {
        // Frames bloom in, slightly staggered
        withAnimation(.easeOut(duration: 0.45)) {
            landScale = 1.0
            landOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.45).delay(0.12)) {
            portScale = 1.0
            portOpacity = 1.0
        }
        // Record dot pops in
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.30)) {
            dotScale = 1.0
        }
        // Subtle pulse keeps things alive while the camera warms up
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true).delay(0.75)) {
            dotPulse = 1.12
        }
    }
}
