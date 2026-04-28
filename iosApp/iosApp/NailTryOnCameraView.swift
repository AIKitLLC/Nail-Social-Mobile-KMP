import SwiftUI
import AVFoundation
import UIKit

/// Camera-based nail try-on with TensorFlow Lite + Vision framework
struct NailTryOnCameraView: View {
    let designId: String?
    let onBack: () -> Void

    @StateObject private var cameraManager = CameraManager()
    @State private var selectedPattern = 0
    @State private var showDebug = false
    @State private var showDetectorTest = false
    @State private var captureFlashTrigger = 0
    @State private var sparkleBurstTrigger = 0
    @State private var rippleTrigger = 0
    @State private var rippleOrigin: CGPoint = .zero
    @State private var rippleColor: Color = .white
    @State private var maskAppeared = false
    @State private var hasSeenFirstDetection = false
    @State private var showCapturePreview = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false
    @State private var previousMask: UIImage?
    @State private var maskPulse: CGFloat = 1.0

    private let patternNames = NailPatternFactory.patternNames
    private let patternImages: [UIImage] = (0..<NailPatternFactory.patternCount).map { NailPatternFactory.image(for: $0) }

    var body: some View {
        ZStack {
            if cameraManager.isSimulator {
                simulatorView
            } else if let error = cameraManager.error {
                cameraErrorView(error)
            } else {
                // 1. Camera preview
                CameraPreview(session: cameraManager.session)
                    .ignoresSafeArea()

                // 2. Live mask overlay with smooth cross-fade between frames +
                //    animated shimmer. Two stacked Image views keyed by the
                //    UIImage instance — SwiftUI cross-fades them under
                //    .animation(.smoothFade) for buttery tracking.
                if let mask = cameraManager.maskImage {
                    ZStack {
                        Image(uiImage: mask)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .opacity(maskAppeared ? 0.78 : 0.0)
                            .scaleEffect(maskPulse)
                            .id(ObjectIdentifier(mask))
                            .transition(.opacity)
                            .blendMode(.normal)

                        Image(uiImage: mask)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .mask(ShimmerOverlay())
                            .opacity(maskAppeared ? 0.55 : 0.0)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .animation(.smoothFade, value: ObjectIdentifier(mask))
                    .onAppear {
                        withAnimation(.snappySpring) { maskAppeared = true }
                        if !hasSeenFirstDetection {
                            hasSeenFirstDetection = true
                            cameraManager.firstDetectionHandled = true
                            Haptics.success()
                            sparkleBurstTrigger &+= 1
                        }
                    }
                    .onDisappear {
                        maskAppeared = false
                    }
                }

                // 3. Hand-search reticle when no mask yet
                if cameraManager.maskImage == nil {
                    HandSearchReticle()
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }

            // The camera-only chrome is hidden on simulator + error fallback
            // so the fallback messages aren't covered by pattern strip etc.
            if cameraIsActive {
                cameraChrome
            } else {
                // simulator/error fallback gets only its own back button
                EmptyView()
            }
        }
        .onAppear {
            cameraManager.start()
            if !hasSeenOnboarding && cameraIsActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.smoothFade) { showOnboarding = true }
                }
            }
        }
        .onDisappear {
            cameraManager.stop()
        }
        .onChange(of: showOnboarding) { _, newValue in
            if !newValue { hasSeenOnboarding = true }
        }
        .onChange(of: cameraManager.maskImage == nil) { _, isNil in
            if isNil { maskAppeared = false }
        }
        .sheet(isPresented: $showDetectorTest) {
            NailDetectorTestView(onClose: { showDetectorTest = false })
        }
        .sheet(isPresented: $showCapturePreview) {
            if let img = cameraManager.lastCapture, let url = cameraManager.lastCaptureURL {
                CapturePreviewView(image: img, fileURL: url, onClose: { showCapturePreview = false })
            }
        }
    }

    private var cameraIsActive: Bool {
        !cameraManager.isSimulator && cameraManager.error == nil
    }

    @ViewBuilder
    private var cameraChrome: some View {
        ZStack {
            // Ambient drifting sparkles for "AR magic" feel
            AmbientParticles()
                .ignoresSafeArea()
                .opacity(0.55)

            // Pattern-change ripple
            PatternRipple(trigger: rippleTrigger, origin: rippleOrigin, color: rippleColor)

            // First-detection sparkle burst — radiates from screen center
            SparkleBurst(trigger: sparkleBurstTrigger)
                .ignoresSafeArea()

            // Capture flash overlay (top of stack)
            CaptureFlash(trigger: captureFlashTrigger)

            // Top bar — back button + scan status pill + debug toggles
            VStack {
                HStack(alignment: .center, spacing: 10) {
                    Button(action: { Haptics.light(); onBack() }) {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Spacer()

                    VStack(spacing: 6) {
                        ARScanPill(active: cameraManager.isDetecting)
                            .animation(.smoothFade, value: cameraManager.isDetecting)
                        if cameraManager.componentsFound > 0 {
                            ConfidenceDots(value: min(cameraManager.confidence, 1))
                                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        }
                    }
                    .animation(.smoothFade, value: cameraManager.componentsFound)

                    Spacer()

                    Button(action: { showDetectorTest = true }) {
                        Image(systemName: "photo.stack.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
            }

            // Bottom panel: pattern selector + capture button
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 14) {
                    HStack(spacing: 18) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(Array(patternNames.enumerated()), id: \.offset) { index, name in
                                    PatternThumbnail(
                                        name: name,
                                        isSelected: index == selectedPattern,
                                        baseColor: Color(NailPatternFactory.tintColor(for: index)),
                                        patternImage: patternImages[safe: index],
                                        onTap: {
                                            withAnimation(.snappySpring) {
                                                selectedPattern = index
                                            }
                                            cameraManager.selectPattern(index)
                                            triggerPatternRipple(for: index)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 6)
                        }

                        CaptureButton(onTap: capture)
                            .padding(.trailing, 18)
                    }
                }
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55), .black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                )
                .tiltParallax(6)

            }

            // First-launch onboarding cascade
            OnboardingCascade(isVisible: $showOnboarding)
                .zIndex(100)

            // Floating recent capture peek (bottom-right above the panel)
            if let last = cameraManager.lastCapture {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        RecentCapturePeek(image: last) {
                            showCapturePreview = true
                        }
                        .id(cameraManager.lastCaptureURL?.lastPathComponent ?? "peek")
                        .tiltParallax(10)
                        .padding(.trailing, DS.Space.lg)
                        .padding(.bottom, 110)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func capture() {
        captureFlashTrigger &+= 1
        cameraManager.captureSnapshot { _ in /* state updated by manager */ }
    }

    /// Origin near the pattern strip's vertical center, biased horizontally to
    /// feel like the ripple emanates from the chip itself. Uses the keyWindow
    /// bounds at trigger time so it adapts to any device size.
    private func triggerPatternRipple(for index: Int) {
        let bounds = currentScreenBounds()
        // Bottom panel sits ~12pt vertical padding + 70pt thumbnail rows above
        // the safe-area bottom; use a constant relative anchor instead of a
        // pixel-exact one so it works on every device size.
        let panelY = bounds.height - 90
        let stripWidth = bounds.width - 32 // matches panel padding
        let chipSpacing = stripWidth / CGFloat(max(patternNames.count, 1))
        let xCenter = 16 + chipSpacing * (CGFloat(index) + 0.5)
        rippleOrigin = CGPoint(x: xCenter, y: panelY)
        rippleColor = Color(NailPatternFactory.tintColor(for: index))
        rippleTrigger &+= 1

        // Quick "absorb" pulse on the existing mask — feels like the new
        // polish is being soaked in.
        withAnimation(.interpolatingSpring(stiffness: 220, damping: 12)) {
            maskPulse = 1.06
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.interpolatingSpring(stiffness: 260, damping: 18)) {
                maskPulse = 1.0
            }
        }
    }

    /// Current key window's bounds — falls back to UIScreen.main.bounds if
    /// the window can't be located (e.g. very early in app lifecycle).
    private func currentScreenBounds() -> CGRect {
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            return window.bounds
        }
        return UIScreen.main.bounds
    }

    private var simulatorView: some View {
        ZStack {
            // Brand backdrop
            LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.06, blue: 0.18),
                    Color(red: 0.05, green: 0.02, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Faint ambient drift
            AmbientParticles(density: 18)
                .ignoresSafeArea()
                .opacity(0.45)

            VStack(spacing: DS.Space.xl) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [DS.Brand.pinkAccent.opacity(0.6), .clear],
                                center: .center,
                                startRadius: 8,
                                endRadius: 110
                            )
                        )
                        .frame(width: 200, height: 200)
                        .blur(radius: 20)

                    Image(systemName: "hand.raised.fingers.spread.fill")
                        .font(.system(size: 80, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, DS.Brand.pinkAccent],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                VStack(spacing: 6) {
                    Text("Simulator Mode")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    Text("Camera is unavailable on the simulator.\nUse a physical device to try on polish.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Space.xxl)
                }

                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                            .shadow(color: .green, radius: 4)
                        Text("Mock detection active")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Text("Selected pattern: \(patternNames[selectedPattern])")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(DS.Space.md)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 0.6)
                        )
                )

                Button(action: { Haptics.light(); onBack() }) {
                    Text("Back")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.xl)
                        .padding(.vertical, DS.Space.sm)
                        .background(Capsule().fill(.white.opacity(0.15)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.3)))
                }
                .buttonStyle(BounceButtonStyle())
            }
        }
    }

    private func cameraErrorView(_ error: String) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)

                Text("Camera Unavailable")
                    .font(.title3.bold())
                    .foregroundColor(.white)

                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

}

// MARK: - Camera Manager

class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var error: String?
    @Published var isSimulator: Bool = false
    @Published var maskImage: UIImage?
    @Published var isDetecting: Bool = false
    @Published var confidence: Float = 0
    @Published var componentsFound: Int = 0
    @Published var lastCapture: UIImage?
    @Published var lastCaptureURL: URL?

    /// Set to true after we've fired the "first detection" haptic so we don't
    /// repeat it every frame.
    var firstDetectionHandled: Bool = false

    /// Latest oriented camera frame (used to compose snapshots).
    private var latestFrame: UIImage?
    private let snapshotQueue = DispatchQueue(label: "nail.snapshot.queue")

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let output = AVCaptureVideoDataOutput()
    private let detector = NailDetectorIOS()
    private let inferenceQueue = DispatchQueue(label: "nail.inference.queue", qos: .userInitiated)
    private var frameCount = 0
    private let processEveryNFrames = 3

    override init() {
        super.init()
        #if targetEnvironment(simulator)
        isSimulator = true
        #endif
        // Select default pattern on init
        selectPattern(0)
    }

    func start() {
        guard !isSimulator else { return }
        sessionQueue.async { [weak self] in self?.setupCamera() }
    }

    func stop() {
        guard !isSimulator else { return }
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
    }

    func selectPattern(_ index: Int) {
        guard index >= 0, index < NailPatternFactory.patternCount else {
            detector.patternImage = nil
            return
        }
        detector.patternImage = NailPatternFactory.image(for: index)
    }

    /// Compose the latest oriented camera frame + current mask into a single
    /// UIImage, save it to Documents, and call back on the main queue.
    func captureSnapshot(completion: @escaping (URL?) -> Void) {
        let mask = self.maskImage
        snapshotQueue.async { [weak self] in
            guard let self = self, let frame = self.latestFrame else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: frame.size, format: format)
            let composed = renderer.image { _ in
                frame.draw(in: CGRect(origin: .zero, size: frame.size))
                if let mask = mask {
                    mask.draw(in: CGRect(origin: .zero, size: frame.size), blendMode: .normal, alpha: 0.85)
                }
            }
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fname = "nail-\(Int(Date().timeIntervalSince1970)).jpg"
            let url = docs.appendingPathComponent(fname)
            if let data = composed.jpegData(compressionQuality: 0.92) {
                try? data.write(to: url)
                DispatchQueue.main.async {
                    self.lastCapture = composed
                    self.lastCaptureURL = url
                    completion(url)
                }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    private func setupCamera() {
        // Higher resolution gives the segmentation model more detail in the
        // hand-cropped region. .hd1280x720 is supported on every modern iPhone
        // and keeps inference budget reasonable.
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            DispatchQueue.main.async { self.error = "No camera device found." }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) } else { return }
        } catch {
            DispatchQueue.main.async { self.error = "Camera access denied: \(error.localizedDescription)" }
            return
        }

        output.setSampleBufferDelegate(self, queue: sessionQueue)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        if session.canAddOutput(output) { session.addOutput(output) }
        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        session.startRunning()
    }

    /// Apply the same 90° rotation to the preview connection so the preview
    /// frames the user sees match the data buffers fed to the detector.
    func configurePreviewRotation(_ previewLayer: AVCaptureVideoPreviewLayer) {
        if let connection = previewLayer.connection,
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    private func pixelBufferToUIImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // BGRA format (kCVPixelFormatType_32BGRA)
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let context = CGContext(
            data: baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else { return nil }

        guard let cgImage = context.makeImage() else { return nil }
        // No orientation - raw camera frame. NailDetectorIOS handles orientation.
        return UIImage(cgImage: cgImage)
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {
        frameCount += 1
        guard frameCount % processEveryNFrames == 0 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        inferenceQueue.async { [weak self] in
            guard let self = self else { return }
            guard let image = self.pixelBufferToUIImage(pixelBuffer) else { return }

            // Cache the most-recent oriented frame so the snapshot button can
            // build a final image without racing the camera output.
            self.snapshotQueue.async { self.latestFrame = image }

            DispatchQueue.main.async { self.isDetecting = true }
            guard let result = self.detector.detectNails(image) else {
                DispatchQueue.main.async { self.isDetecting = false }
                return
            }

            DispatchQueue.main.async {
                withAnimation(.smoothFade) {
                    self.maskImage = result.maskImage
                }
                // Smooth confidence (light low-pass for HUD)
                let blended = self.confidence * 0.6 + result.maxConfidence * 0.4
                withAnimation(.easeOut(duration: 0.25)) {
                    self.confidence = blended
                    self.componentsFound = result.componentsFound
                }
                self.isDetecting = false
            }
        }
    }
}

// MARK: - Camera Preview

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraHostView {
        let view = CameraHostView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        // Match the output connection's 90° rotation so preview and pipeline
        // see the same frame orientation.
        if let connection = view.previewLayer.connection,
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return view
    }

    func updateUIView(_ uiView: CameraHostView, context: Context) {}
}

class CameraHostView: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}
