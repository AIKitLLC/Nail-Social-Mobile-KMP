import SwiftUI
import UIKit
import CoreHaptics
import CoreMotion
import Combine

// MARK: - Array safe subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Haptics

enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
    }
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Animation presets

extension Animation {
    static let snappySpring = Animation.interpolatingSpring(stiffness: 240, damping: 22)
    static let bouncyPop = Animation.interpolatingSpring(stiffness: 320, damping: 14)
    static let smoothFade = Animation.easeInOut(duration: 0.28)
    static let pulse = Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true)
}

// MARK: - Nail tip shape (used in pattern thumbnails)

struct NailTipShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        // tear-drop / nail silhouette: rounded top, gentle taper
        p.move(to: CGPoint(x: rect.minX + w * 0.15, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY + h * 0.45)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - w * 0.15, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.minY + h * 0.45)
        )
        p.addLine(to: CGPoint(x: rect.minX + w * 0.15, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Pattern thumbnail with gloss + animated selection halo

struct PatternThumbnail: View {
    let name: String
    let isSelected: Bool
    let baseColor: Color
    /// Optional rendered pattern image used to fill the chip — gives users a
    /// real-preview of what they'll get on the nail.
    var patternImage: UIImage? = nil
    var onTap: () -> Void = {}

    @State private var pressed = false
    @State private var haloPhase: CGFloat = 0

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // animated halo for the selected state
                if isSelected {
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [.white, baseColor, .white.opacity(0.3), baseColor, .white],
                                center: .center,
                                angle: .degrees(haloPhase)
                            ),
                            lineWidth: 2.5
                        )
                        .frame(width: 64, height: 64)
                        .blur(radius: 0.5)
                        .onAppear {
                            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                                haloPhase = 360
                            }
                        }
                }

                // nail-shaped chip filled with the actual pattern image (or
                // a gradient fallback when no image is supplied).
                Group {
                    if let img = patternImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .clipShape(NailTipShape())
                    } else {
                        NailTipShape()
                            .fill(
                                LinearGradient(
                                    colors: [baseColor.opacity(0.95), baseColor.opacity(0.65)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
                .overlay(
                    // gloss highlight
                    NailTipShape()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.42), .white.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .padding(4)
                        .blendMode(.plusLighter)
                )
                .overlay(
                    NailTipShape()
                        .stroke(.white.opacity(isSelected ? 0.55 : 0.18), lineWidth: 0.8)
                )
                .frame(width: 38, height: 50)
                .shadow(color: baseColor.opacity(0.45), radius: isSelected ? 10 : 4, y: 2)
                .scaleEffect(pressed ? 0.86 : (isSelected ? 1.08 : 1.0))
                .animation(.bouncyPop, value: isSelected)
                .animation(.snappySpring, value: pressed)
            }
            .frame(width: 64, height: 70)

            Text(name)
                .font(.caption2.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.75))
                .lineLimit(1)
        }
        .frame(width: 70)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.selection()
            withAnimation(.snappySpring) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.snappySpring) { pressed = false }
            }
            onTap()
        }
    }
}

// MARK: - Animated AR scanning pill

struct ARScanPill: View {
    let active: Bool
    @State private var sweep: CGFloat = -1

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.25), lineWidth: 2)
                    .frame(width: 14, height: 14)
                Circle()
                    .trim(from: 0, to: 0.35)
                    .stroke(
                        LinearGradient(
                            colors: [.white, .white.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(active ? 360 : 0))
                    .animation(active ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: active)
            }

            Text(active ? "AI scanning" : "AR ready")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.4), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.6
                        )
                )
        )
        // a subtle sweep highlight
        .overlay(
            GeometryReader { geo in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.18), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: sweep * geo.size.width * 1.4)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            .clipShape(Capsule())
        )
        .onAppear {
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                sweep = 1
            }
        }
    }
}

// MARK: - Hand-search reticle (shown when no detection yet)

struct HandSearchReticle: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            // outer pulse ring
            Circle()
                .stroke(.white.opacity(0.22), lineWidth: 1.5)
                .frame(width: 220, height: 220)
                .scaleEffect(pulse ? 1.18 : 0.94)
                .opacity(pulse ? 0.0 : 0.9)
                .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)

            Circle()
                .stroke(.white.opacity(0.4), lineWidth: 1.5)
                .frame(width: 180, height: 180)

            Image(systemName: "hand.raised.fingers.spread.fill")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.white.opacity(0.55))

            VStack {
                Spacer()
                Text("Place your hand in frame")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 200)
            }
        }
        .onAppear { pulse = true }
        .allowsHitTesting(false)
    }
}

// MARK: - Capture / shutter button

struct CaptureButton: View {
    var onTap: () -> Void
    @State private var pressed = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: 3)
                .frame(width: 72, height: 72)

            Circle()
                .fill(.white)
                .frame(width: 58, height: 58)
                .scaleEffect(pressed ? 0.84 : 1)
                .animation(.snappySpring, value: pressed)
        }
        .contentShape(Circle())
        .onTapGesture {
            Haptics.success()
            withAnimation(.snappySpring) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.snappySpring) { pressed = false }
            }
            onTap()
        }
    }
}

// MARK: - Animated shimmer over the mask

struct ShimmerOverlay: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.55), location: 0.5),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.35, height: geo.size.height * 1.2)
            .rotationEffect(.degrees(20))
            .offset(x: phase * geo.size.width * 1.5)
            .blendMode(.plusLighter)
            .onAppear {
                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Sparkle burst (first detection celebration)

struct SparkleBurst: View {
    let trigger: Int
    private let particleCount = 22

    var body: some View {
        TimelineView(.animation) { _ in
            ZStack {
                ForEach(0..<particleCount, id: \.self) { i in
                    Particle(seed: i, trigger: trigger)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private struct Particle: View {
        let seed: Int
        let trigger: Int
        @State private var animate = false
        @State private var lastTrigger = -1

        var body: some View {
            let angle = Double(seed) / 22.0 * .pi * 2
            let radius: CGFloat = animate ? CGFloat.random(in: 130...230) : 0
            let dx = CGFloat(cos(angle)) * radius
            let dy = CGFloat(sin(angle)) * radius
            let scale: CGFloat = animate ? 0.0 : 1.0

            return Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.92, blue: 0.4), Color(red: 1.0, green: 0.6, blue: 0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(animate ? 0 : 1)
                .scaleEffect(scale)
                .offset(x: dx, y: dy)
                .shadow(color: .yellow.opacity(0.7), radius: 6)
                .onChange(of: trigger) { _, new in
                    guard new != lastTrigger else { return }
                    lastTrigger = new
                    animate = false
                    withAnimation(.easeOut(duration: 1.0).delay(Double(seed) * 0.012)) {
                        animate = true
                    }
                }
        }
    }
}

// MARK: - Confidence dots HUD

struct ConfidenceDots: View {
    /// 0...1 confidence score
    let value: Float
    private let count = 5

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                let filled = Float(i) < value * Float(count)
                Circle()
                    .fill(filled ? Color.green.opacity(0.95) : Color.white.opacity(0.18))
                    .frame(width: 6, height: 6)
                    .shadow(color: filled ? .green.opacity(0.7) : .clear, radius: 3)
                    .animation(.smoothFade, value: filled)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Recent capture peek pill

struct RecentCapturePeek: View {
    let image: UIImage
    var onTap: () -> Void

    @State private var pressed = false
    @State private var slideIn = false

    var body: some View {
        Button(action: { Haptics.light(); onTap() }) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.85), lineWidth: 2)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
            }
            .frame(width: 60, height: 80)
            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            .scaleEffect(pressed ? 0.92 : 1.0)
            .offset(x: slideIn ? 0 : 90)
            .opacity(slideIn ? 1 : 0)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.bouncyPop.delay(0.05)) { slideIn = true }
        }
        .onLongPressGesture(minimumDuration: 0.0, pressing: { p in
            withAnimation(.snappySpring) { pressed = p }
        }, perform: {})
    }
}

// MARK: - Capture preview sheet (share + done)

struct CapturePreviewView: View {
    let image: UIImage
    let fileURL: URL
    var onClose: () -> Void

    @State private var showShare = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding()
                .scaleEffect(appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)
                .animation(.bouncyPop, value: appeared)

            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                    Button(action: { Haptics.light(); showShare = true }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding()
                Spacer()
                Text(fileURL.lastPathComponent)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.bottom, 24)
            }
        }
        .onAppear { appeared = true }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [fileURL])
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Animated avatar

struct AnimatedAvatar: View {
    @State private var phase: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let angle = (t * 30).truncatingRemainder(dividingBy: 360)
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Color(red: 1.0, green: 0.55, blue: 0.72),
                                Color(red: 0.55, green: 0.27, blue: 0.78),
                                Color(red: 0.94, green: 0.20, blue: 0.45),
                                Color(red: 1.0, green: 0.85, blue: 0.50),
                                Color(red: 1.0, green: 0.55, blue: 0.72)
                            ],
                            center: .center,
                            angle: .degrees(angle)
                        )
                    )

                Circle()
                    .fill(.white.opacity(0.85))
                    .scaleEffect(0.7)
                    .blur(radius: 4)
                    .opacity(0.0)

                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 4)
            }
        }
        .clipShape(Circle())
        .shadow(color: DS.Brand.pinkPrimary.opacity(0.45), radius: 12)
    }
}

// MARK: - Filter chip

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
                .background(
                    Capsule()
                        .fill(isSelected
                              ? AnyShapeStyle(DS.Brand.primaryGradient)
                              : AnyShapeStyle(Color(.tertiarySystemBackground)))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.clear : Color.primary.opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: isSelected ? DS.Brand.pinkPrimary.opacity(0.3) : .clear, radius: 6, y: 2)
        }
        .buttonStyle(BounceButtonStyle())
    }
}

// MARK: - Skeleton card (loading placeholder)

struct SkeletonCard: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            shimmerBlock
                .aspectRatio(0.78, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                shimmerBlock.frame(height: 10)
                shimmerBlock.frame(height: 10).padding(.trailing, 40)
            }
            .padding(.horizontal, DS.Space.xs)
            .padding(.bottom, DS.Space.sm)
        }
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .cardShadow()
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private var shimmerBlock: some View {
        GeometryReader { _ in
            Rectangle()
                .fill(Color(.systemGray5))
                .overlay(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.55), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .scaleEffect(x: 0.6, y: 1, anchor: .center)
                    .offset(x: phase * 220)
                    .blendMode(.plusLighter)
                )
                .clipped()
        }
    }
}

// MARK: - Pattern apply ripple (radial reveal)

struct PatternRipple: View {
    /// Increment to fire a new ripple
    let trigger: Int
    /// Origin in screen coords
    var origin: CGPoint
    /// Tint color of the ripple
    var color: Color = .white

    @State private var lastTrigger = -1
    @State private var radius: CGFloat = 0
    @State private var opacity: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .stroke(
                        RadialGradient(
                            colors: [color.opacity(0.0), color.opacity(0.85), color.opacity(0.0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 120
                        ),
                        lineWidth: 28
                    )
                    .frame(width: radius * 2, height: radius * 2)
                    .position(origin)
                    .opacity(opacity)
                    .blendMode(.plusLighter)
            }
            .ignoresSafeArea()
            .onChange(of: trigger) { _, new in
                guard new != lastTrigger else { return }
                lastTrigger = new
                radius = 0
                opacity = 0.85
                let target = max(geo.size.width, geo.size.height) * 1.2
                withAnimation(.easeOut(duration: 0.85)) {
                    radius = target
                    opacity = 0
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - CoreMotion tilt parallax

final class MotionManager: ObservableObject {
    static let shared = MotionManager()
    private let manager = CMMotionManager()

    @Published var roll: Double = 0   // X tilt (-π/2 ... +π/2)
    @Published var pitch: Double = 0  // Y tilt

    init() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self = self, let m = motion else { return }
            // Low-pass smoothing
            let alpha = 0.18
            self.roll = self.roll * (1 - alpha) + m.attitude.roll * alpha
            self.pitch = self.pitch * (1 - alpha) + m.attitude.pitch * alpha
        }
    }

    deinit { manager.stopDeviceMotionUpdates() }
}

struct TiltParallax: ViewModifier {
    @ObservedObject private var motion = MotionManager.shared
    /// Maximum lateral movement, in points.
    var magnitude: CGFloat = 8
    /// Max rotation degrees.
    var rotateMagnitude: Double = 4

    func body(content: Content) -> some View {
        let xOffset = CGFloat(sin(motion.roll)) * magnitude
        let yOffset = CGFloat(sin(motion.pitch)) * magnitude * 0.4
        let yaw = motion.roll * rotateMagnitude
        let tilt = motion.pitch * rotateMagnitude * 0.5
        return content
            .offset(x: xOffset, y: yOffset)
            .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0))
            .rotation3DEffect(.degrees(-tilt), axis: (x: 1, y: 0, z: 0))
    }
}

extension View {
    func tiltParallax(_ magnitude: CGFloat = 8) -> some View {
        modifier(TiltParallax(magnitude: magnitude))
    }
}

// MARK: - Ambient floating sparkle particles

struct AmbientParticles: View {
    var density: Int = 14
    @State private var seeds: [CGFloat] = []

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { ctx in
            Canvas { canvasCtx, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                for (i, seed) in seeds.enumerated() {
                    let speed = 14 + Double(i % 5) * 6
                    let cycle = (t * speed / 200 + Double(seed)).truncatingRemainder(dividingBy: 1.0)
                    let xPhase = sin((t * 0.4) + Double(seed) * 12) * 24
                    let x = CGFloat(seed) * size.width + CGFloat(xPhase)
                    let y = size.height * (1.05 - CGFloat(cycle))
                    let alpha = 0.0 + 0.55 * (sin(CGFloat(cycle) * .pi))
                    let r: CGFloat = 1.6 + CGFloat((Int(seed * 7)) % 3)
                    let rect = CGRect(x: x.truncatingRemainder(dividingBy: size.width) - r,
                                      y: y - r,
                                      width: r * 2, height: r * 2)
                    canvasCtx.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(Double(alpha)))
                    )
                }
            }
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
        .onAppear {
            if seeds.isEmpty {
                seeds = (0..<density).map { _ in CGFloat.random(in: 0...1) }
            }
        }
    }
}

// MARK: - Onboarding tooltip cascade

struct OnboardingCascade: View {
    @Binding var isVisible: Bool

    @State private var step: Int = 0
    @State private var fadeIn = false

    private let steps: [(icon: String, title: String, hint: String)] = [
        ("hand.raised.fingers.spread.fill", "Place your hand", "Hold steady — AI scans your fingertips."),
        ("paintpalette.fill", "Pick a polish", "Tap any chip to try it on instantly."),
        ("camera.fill", "Capture & share", "Tap the shutter for a perfect snapshot.")
    ]

    var body: some View {
        if isVisible {
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer().frame(height: 32)

                    let cur = steps[min(step, steps.count - 1)]

                    Image(systemName: cur.icon)
                        .font(.system(size: 50, weight: .light))
                        .foregroundStyle(LinearGradient(colors: [.white, .pink], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .pink.opacity(0.5), radius: 12)
                        .scaleEffect(fadeIn ? 1 : 0.7)
                        .opacity(fadeIn ? 1 : 0)
                        .id("icon-\(step)")
                        .transition(.scale.combined(with: .opacity))

                    Text(cur.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .id("title-\(step)")
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                    Text(cur.hint)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .id("hint-\(step)")
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                    Spacer()

                    HStack(spacing: 6) {
                        ForEach(0..<steps.count, id: \.self) { i in
                            Capsule()
                                .fill(i == step ? Color.white : .white.opacity(0.3))
                                .frame(width: i == step ? 20 : 6, height: 6)
                                .animation(.snappySpring, value: step)
                        }
                    }

                    Button(action: advance) {
                        Text(step == steps.count - 1 ? "Let's go" : "Next")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule()
                                    .fill(LinearGradient(colors: [.white, Color(white: 0.92)], startPoint: .top, endPoint: .bottom))
                            )
                            .shadow(color: .white.opacity(0.4), radius: 12)
                    }
                    .padding(.horizontal, 40)

                    Button("Skip") {
                        Haptics.light()
                        dismiss()
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 6)
                    .padding(.bottom, 28)
                }
            }
            .transition(.opacity)
            .onAppear {
                withAnimation(.bouncyPop.delay(0.1)) { fadeIn = true }
            }
        }
    }

    private func advance() {
        Haptics.selection()
        if step < steps.count - 1 {
            withAnimation(.snappySpring) { step += 1 }
        } else {
            dismiss()
        }
    }

    private func dismiss() {
        withAnimation(.smoothFade) { isVisible = false }
    }
}

// MARK: - Capture flash

struct CaptureFlash: View {
    let trigger: Int
    @State private var flashing = false

    var body: some View {
        Color.white
            .opacity(flashing ? 0.85 : 0)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onChange(of: trigger) { _, _ in
                flashing = true
                withAnimation(.easeOut(duration: 0.32)) { flashing = false }
            }
    }
}
