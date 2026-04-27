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

    private let patternNames = ["Classic Red", "French", "Pink Glitter", "Blue Gradient", "Gold", "Purple"]

    var body: some View {
        ZStack {
            if cameraManager.isSimulator {
                simulatorView
            } else if let error = cameraManager.error {
                cameraErrorView(error)
            } else {
                // Camera preview
                CameraPreview(session: cameraManager.session)
                    .ignoresSafeArea()

                // Mask overlay (from detection pipeline)
                if let mask = cameraManager.maskImage {
                    Image(uiImage: mask)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(0.65)
                        .allowsHitTesting(false)
                }

                // Debug overlay
                if showDebug, let debug = cameraManager.debugImage {
                    Image(uiImage: debug)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(0.3)
                        .allowsHitTesting(false)
                }
            }

            // Bottom controls
            VStack {
                Spacer()

                // Detection status
                if cameraManager.isDetecting {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Detecting nails...")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Debug toggle
                HStack {
                    Spacer()
                    Button(action: { showDebug.toggle() }) {
                        Image(systemName: showDebug ? "ladybug.fill" : "ladybug")
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
                                    cameraManager.selectPattern(index)
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
        let colors: [Color] = [.red, .white, .pink, .blue, .yellow, .purple]
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
    @Published var maskImage: UIImage?
    @Published var debugImage: UIImage?
    @Published var isDetecting: Bool = false

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
        // Generate pattern image based on selection
        let colors: [UIColor] = [
            .red, .white, .systemPink, .systemBlue, .systemYellow, .purple
        ]
        guard index >= 0, index < colors.count else {
            detector.patternImage = nil
            return
        }

        let size = CGSize(width: 256, height: 256)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        colors[index].setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        // Add some texture effect
        let patternImg = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        detector.patternImage = patternImg
    }

    private func setupCamera() {
        session.sessionPreset = .medium

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
        if session.canAddOutput(output) { session.addOutput(output) }
        if let connection = output.connection(with: .video) {
            connection.videoRotationAngle = 90
        }
        session.startRunning()
    }

    private func pixelBufferToUIImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let context = CGContext(
            data: baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else { return nil }

        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
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

            DispatchQueue.main.async { self.isDetecting = true }
            guard let result = self.detector.detectNails(image) else {
                DispatchQueue.main.async { self.isDetecting = false }
                return
            }

            DispatchQueue.main.async {
                self.maskImage = result.maskImage
                self.debugImage = result.inputImage
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
