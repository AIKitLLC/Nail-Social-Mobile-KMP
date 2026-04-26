import SwiftUI
import AVFoundation

/// Camera-based nail try-on with CoreML + Vision
struct NailTryOnCameraView: View {
    let designId: String?
    let onBack: () -> Void

    @StateObject private var cameraManager = CameraManager()
    @State private var detectedMask: CGImage?
    @State private var selectedPattern = 0
    @State private var showDebug = false

    private let patternNames = ["Classic Red", "French", "Pink Glitter", "Blue Gradient", "Gold", "Purple"]

    var body: some View {
        ZStack {
            if cameraManager.isSimulator {
                // Simulator fallback UI
                simulatorView
            } else if let error = cameraManager.error {
                // Camera error state
                cameraErrorView(error)
            } else {
                // Camera preview
                CameraPreview(session: cameraManager.session)
                    .ignoresSafeArea()

                // Mask overlay
                if let mask = detectedMask {
                    Image(mask, scale: 1, label: Text("Nail Mask"))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(0.6)
                        .allowsHitTesting(false)
                }
            }

            // Bottom controls (always visible)
            VStack {
                Spacer()

                // Debug toggle
                HStack {
                    Spacer()
                    Button(action: { showDebug.toggle() }) {
                        Image(systemName: "ladybug")
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding()
                }

                // Pattern selector
                VStack(spacing: 8) {
                    Text(designId != nil ? "Custom Design" : "Select Nail Pattern")
                        .font(.caption)
                        .foregroundColor(.white)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(patternNames.enumerated()), id: \.offset) { index, name in
                                PatternThumbnailIOS(
                                    name: name,
                                    isSelected: index == selectedPattern,
                                    patternColor: patternColor(index)
                                )
                                .onTapGesture {
                                    selectedPattern = index
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 16)
                .background {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }

            // Back button
            VStack {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding()
                    Spacer()
                }
                Spacer()
            }
        }
        .onAppear {
            cameraManager.start()
        }
        .onDisappear {
            cameraManager.stop()
        }
    }

    private var simulatorView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "hand.raised.fingers.spread")
                    .font(.system(size: 80))
                    .foregroundColor(.pink.opacity(0.6))

                Text("Simulator Mode")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text("Camera is not available on the simulator.\nUse a physical device to try on nail designs.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Mock detection indicator
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Mock hand detection active")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    Text("Pattern: \(patternNames[selectedPattern])")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
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

    private func patternColor(_ index: Int) -> Color {
        let colors: [Color] = [
            .red, .white, .pink, .blue, .yellow, .purple
        ]
        return colors[index % colors.count]
    }
}

struct PatternThumbnailIOS: View {
    let name: String
    let isSelected: Bool
    let patternColor: Color

    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 8)
                .fill(patternColor)
                .frame(width: 56, height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white, lineWidth: isSelected ? 2 : 0)
                )

            Text(name)
                .font(.caption2)
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .frame(width: 64)
    }
}

// MARK: - Camera Manager

class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var error: String?
    @Published var isSimulator: Bool = false

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let output = AVCaptureVideoDataOutput()

    override init() {
        super.init()
        #if targetEnvironment(simulator)
        isSimulator = true
        #endif
    }

    func start() {
        guard !isSimulator else { return }

        sessionQueue.async { [weak self] in
            self?.setupCamera()
        }
    }

    func stop() {
        guard !isSimulator else { return }

        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    private func setupCamera() {
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            DispatchQueue.main.async {
                self.error = "No camera device found. Please use a device with a camera."
            }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)

            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                DispatchQueue.main.async {
                    self.error = "Could not add camera input to session."
                }
                return
            }
        } catch {
            DispatchQueue.main.async {
                self.error = "Camera access denied: \(error.localizedDescription)"
            }
            return
        }

        output.setSampleBufferDelegate(self, queue: sessionQueue)
        output.alwaysDiscardsLateVideoFrames = true

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        // Set orientation
        if let connection = output.connection(with: .video) {
            connection.videoRotationAngle = 90 // Portrait
        }

        session.startRunning()
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {
        // Process frame with CoreML
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Run nail detection (simplified for now - will use CoreML model)
        // In production, this would call the CoreML model + Vision framework
        processNailDetection(pixelBuffer: pixelBuffer)
    }

    private func processNailDetection(pixelBuffer: CVPixelBuffer) {
        // TODO: Run CoreML Nail Detection model
        // For now, the mask will be shown when we implement the CoreML wrapper
    }
}

// MARK: - Camera Preview (UIViewRepresentable)

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraHostView {
        let view = CameraHostView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraHostView, context: Context) {
        // Frame is updated automatically via layoutSubviews
    }
}

/// UIView subclass that keeps the preview layer sized to its bounds
class CameraHostView: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}
