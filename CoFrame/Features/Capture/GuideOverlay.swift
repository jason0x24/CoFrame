import SwiftUI

struct GuideOverlay: View {
    let kind: GuideLineKind
    let rollDegrees: Double

    var body: some View {
        ZStack {
            if kind.showThirds { ThirdsGrid() }
            if kind.showCrosshair { Crosshair() }
            if kind.showLevel { LevelLine(rollDegrees: rollDegrees) }
        }
        .allowsHitTesting(false)
    }
}

private struct ThirdsGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let color = Color.white.opacity(0.5)
            for i in 1..<3 {
                let x = size.width * CGFloat(i) / 3.0
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }, with: .color(color), lineWidth: 0.5)
                let y = size.height * CGFloat(i) / 3.0
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }, with: .color(color), lineWidth: 0.5)
            }
        }
    }
}

private struct Crosshair: View {
    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2, cy = size.height / 2, len: CGFloat = 18
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: cx - len, y: cy))
                p.addLine(to: CGPoint(x: cx + len, y: cy))
                p.move(to: CGPoint(x: cx, y: cy - len))
                p.addLine(to: CGPoint(x: cx, y: cy + len))
            }, with: .color(Color.white.opacity(0.85)), lineWidth: 1)
        }
    }
}

private struct LevelLine: View {
    let rollDegrees: Double

    var body: some View {
        let level = abs(rollDegrees) < 1.5
        let color = level ? Color.yellow : Color.white.opacity(0.7)
        Canvas { ctx, size in
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.rotate(by: Angle(degrees: rollDegrees))
            let half = min(size.width, size.height) * 0.25
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: -half, y: 0))
                p.addLine(to: CGPoint(x: half, y: 0))
            }, with: .color(color), lineWidth: 1.5)
        }
    }
}
