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
            // Camera preview
            CameraPreview(session: cameraManager.session)
                .ignoresSafeArea()
                .onAppear {
                    cameraManager.start()
                }
                .onDisappear {
                    cameraManager.stop()
                }

            // Mask overlay
            if let mask = detectedMask {
                Image(mask, scale: 1, label: Text("Nail Mask"))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(0.6)
                    .allowsHitTesting(false)
            }

            // Bottom controls
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
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let output = AVCaptureVideoDataOutput()

    func start() {
        sessionQueue.async { [weak self] in
            self?.setupCamera()
            self?.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    private func setupCamera() {
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
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

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}
