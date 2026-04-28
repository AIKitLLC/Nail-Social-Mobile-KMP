import SwiftUI
import PhotosUI
import UIKit

/// Debug screen: pick a hand photo from Photos, run the full detection pipeline,
/// and visualize every intermediate stage. Also writes artifacts to the app's
/// Documents folder so they can be pulled off-device with `devicectl device copy from`.
struct NailDetectorTestView: View {
    let onClose: () -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var result: NailDetectorIOS.DetectionResult?
    @State private var isProcessing = false
    @State private var statusMessage: String = "Pick a hand photo to test the detection pipeline."
    @State private var dumpFolder: String?
    @State private var selectedPattern = 0

    private let detector = NailDetectorIOS()
    private let patternNames = ["Classic Red", "French", "Pink Glitter", "Blue Gradient", "Gold", "Purple"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Label("Pick photo", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }

                    Picker("Pattern", selection: $selectedPattern) {
                        ForEach(Array(patternNames.enumerated()), id: \.offset) { idx, name in
                            Text(name).tag(idx)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedPattern) { _, _ in
                        applyPattern()
                        if let img = sourceImage { runDetection(on: img) }
                    }

                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    if isProcessing {
                        ProgressView("Detecting…")
                    }

                    if let dumpFolder {
                        Text("Artifacts: \(dumpFolder)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                    if let result, let dbg = result.debug, let src = sourceImage {
                        debugMetricsSection(dbg)
                        Divider()
                        stageSection(title: "1. Source photo", image: src)
                        stageSection(
                            title: "2. Oriented full frame  (Vision input)",
                            image: dbg.orientedFullFrame,
                            overlay: { overlayBoxes(in: dbg) }
                        )
                        stageSection(
                            title: "3. Cropped square (TFLite input)",
                            image: dbg.croppedSquare
                        )
                        stageSection(
                            title: "4. Raw mask 256×256 (model output)",
                            image: dbg.rawMask256,
                            background: Color.black
                        )
                        stageSection(
                            title: "5. Composed mask (full-frame overlay)",
                            image: result.maskImage,
                            background: Color.black
                        )
                        stageSection(
                            title: "6. Final overlay on source",
                            image: src,
                            overlay: {
                                Image(uiImage: result.maskImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .opacity(0.7)
                            }
                        )
                    } else if sourceImage != nil {
                        Text("No detection result").foregroundColor(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Detector Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
        .onAppear { applyPattern() }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run {
                        self.sourceImage = img
                        self.result = nil
                    }
                    runDetection(on: img)
                }
            }
        }
    }

    private func applyPattern() {
        let colors: [UIColor] = [.red, .white, .systemPink, .systemBlue, .systemYellow, .purple]
        let size = CGSize(width: 256, height: 256)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        colors[selectedPattern].setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        detector.patternImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
    }

    private func runDetection(on image: UIImage) {
        isProcessing = true
        statusMessage = "Running pipeline…"
        DispatchQueue.global(qos: .userInitiated).async {
            let r = detector.detectNails(image, captureDebug: true)
            let dump = (r?.debug).flatMap { writeDump(source: image, result: r!, debug: $0) }
            DispatchQueue.main.async {
                self.result = r
                self.isProcessing = false
                self.dumpFolder = dump
                if let d = r?.debug {
                    self.statusMessage = "Pipeline OK — maxConf=\(String(format: "%.3f", d.maxConfidence)), components=\(d.componentsFound), orientations=\(d.orientationsFound), hand=\(d.handBBoxInFullFrame != nil ? "yes" : "no")"
                } else if r == nil {
                    self.statusMessage = "Pipeline returned nil"
                }
            }
        }
    }

    private func writeDump(source: UIImage, result: NailDetectorIOS.DetectionResult, debug: NailDetectorIOS.DebugArtifacts) -> String? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let folder = docs.appendingPathComponent("debug").appendingPathComponent(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-"))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        func write(_ img: UIImage, name: String) {
            if let data = img.pngData() {
                try? data.write(to: folder.appendingPathComponent(name))
            }
        }
        write(source, name: "1_source.png")
        write(debug.orientedFullFrame, name: "2_oriented.png")
        write(debug.croppedSquare, name: "3_crop.png")
        write(debug.rawMask256, name: "4_mask256.png")
        write(result.maskImage, name: "5_composed.png")

        let meta: [String: Any] = [
            "maxConfidence": debug.maxConfidence,
            "highConfidencePixelCount": debug.highConfidencePixelCount,
            "componentsFound": debug.componentsFound,
            "orientationsFound": debug.orientationsFound,
            "handBBox": debug.handBBoxInFullFrame.map { ["x": $0.origin.x, "y": $0.origin.y, "w": $0.width, "h": $0.height] } ?? "nil",
            "cropRect": ["x": debug.cropRectInFullFrame.origin.x, "y": debug.cropRectInFullFrame.origin.y, "w": debug.cropRectInFullFrame.width, "h": debug.cropRectInFullFrame.height],
            "fullFrameSize": ["w": debug.orientedFullFrame.size.width, "h": debug.orientedFullFrame.size.height]
        ]
        if let json = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: folder.appendingPathComponent("meta.json"))
        }
        return folder.lastPathComponent
    }

    @ViewBuilder
    private func debugMetricsSection(_ d: NailDetectorIOS.DebugArtifacts) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            metricRow("max confidence", String(format: "%.3f", d.maxConfidence))
            metricRow("high-conf pixels (>0.5)", "\(d.highConfidencePixelCount)")
            metricRow("connected components", "\(d.componentsFound)")
            metricRow("finger orientations", "\(d.orientationsFound)")
            metricRow("hand bbox", d.handBBoxInFullFrame.map { "(\(Int($0.origin.x)),\(Int($0.origin.y))) \(Int($0.width))×\(Int($0.height))" } ?? "not found")
            metricRow("crop rect", "(\(Int(d.cropRectInFullFrame.origin.x)),\(Int(d.cropRectInFullFrame.origin.y))) \(Int(d.cropRectInFullFrame.width))×\(Int(d.cropRectInFullFrame.height))")
            metricRow("full frame", "\(Int(d.orientedFullFrame.size.width))×\(Int(d.orientedFullFrame.size.height))")
        }
        .font(.caption.monospaced())
        .padding(8)
        .background(Color.black.opacity(0.05))
        .cornerRadius(6)
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }

    @ViewBuilder
    private func stageSection<Overlay: View>(
        title: String,
        image: UIImage,
        background: Color = Color(.systemGray6),
        @ViewBuilder overlay: () -> Overlay = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            ZStack {
                background
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                overlay()
            }
            .cornerRadius(6)
        }
    }

    @ViewBuilder
    private func overlayBoxes(in d: NailDetectorIOS.DebugArtifacts) -> some View {
        GeometryReader { geo in
            let imgW = d.orientedFullFrame.size.width
            let imgH = d.orientedFullFrame.size.height
            let scale = min(geo.size.width / imgW, geo.size.height / imgH)
            let drawnW = imgW * scale
            let drawnH = imgH * scale
            let offsetX = (geo.size.width - drawnW) / 2
            let offsetY = (geo.size.height - drawnH) / 2

            ZStack(alignment: .topLeading) {
                if let bbox = d.handBBoxInFullFrame {
                    Rectangle()
                        .stroke(Color.green, lineWidth: 2)
                        .frame(width: bbox.width * scale, height: bbox.height * scale)
                        .offset(x: offsetX + bbox.origin.x * scale,
                                y: offsetY + bbox.origin.y * scale)
                }
                Rectangle()
                    .stroke(Color.yellow, lineWidth: 2)
                    .frame(width: d.cropRectInFullFrame.width * scale, height: d.cropRectInFullFrame.height * scale)
                    .offset(x: offsetX + d.cropRectInFullFrame.origin.x * scale,
                            y: offsetY + d.cropRectInFullFrame.origin.y * scale)
            }
            .allowsHitTesting(false)
        }
    }
}
