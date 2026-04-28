import UIKit

/// Generates distinctive 256×256 pattern textures that the TextureMapper
/// samples onto each detected nail. Each pattern is designed so its top
/// half corresponds to the distal end of a nail (since TextureMapper aligns
/// the texture so its top maps to the nail tip).
enum NailPatternFactory {

    static let patternCount = 6

    static let patternNames = [
        "Classic Red",
        "French",
        "Pink Glitter",
        "Ocean Blue",
        "Gold Mirror",
        "Royal Purple"
    ]

    /// A representative tint for the SwiftUI thumbnail border / halo.
    static func tintColor(for index: Int) -> UIColor {
        switch index {
        case 0: return UIColor(red: 0.86, green: 0.10, blue: 0.18, alpha: 1)
        case 1: return UIColor(red: 0.96, green: 0.86, blue: 0.78, alpha: 1)
        case 2: return UIColor(red: 0.97, green: 0.36, blue: 0.62, alpha: 1)
        case 3: return UIColor(red: 0.16, green: 0.45, blue: 0.85, alpha: 1)
        case 4: return UIColor(red: 0.93, green: 0.74, blue: 0.30, alpha: 1)
        case 5: return UIColor(red: 0.55, green: 0.27, blue: 0.78, alpha: 1)
        default: return .systemPink
        }
    }

    static func image(for index: Int) -> UIImage {
        let size = CGSize(width: 256, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            switch index {
            case 0: drawClassicRed(in: cg, size: size)
            case 1: drawFrench(in: cg, size: size)
            case 2: drawPinkGlitter(in: cg, size: size)
            case 3: drawOceanBlue(in: cg, size: size)
            case 4: drawGoldMirror(in: cg, size: size)
            case 5: drawRoyalPurple(in: cg, size: size)
            default: drawClassicRed(in: cg, size: size)
            }
            // Slight glossy highlight near top — mimics light reflection on
            // the nail's distal end.
            drawGloss(in: cg, size: size)
        }
    }

    // MARK: - Pattern recipes

    private static func drawClassicRed(in cg: CGContext, size: CGSize) {
        drawVerticalGradient(in: cg, size: size, colors: [
            UIColor(red: 0.95, green: 0.15, blue: 0.25, alpha: 1),
            UIColor(red: 0.62, green: 0.05, blue: 0.10, alpha: 1)
        ])
    }

    private static func drawFrench(in cg: CGContext, size: CGSize) {
        // Cream/skin-tone base with ivory white tip on top half.
        let base = UIColor(red: 0.95, green: 0.85, blue: 0.78, alpha: 1)
        let tipColor = UIColor(red: 0.99, green: 0.96, blue: 0.93, alpha: 1) // off-white (skips white-keying)
        cg.setFillColor(base.cgColor)
        cg.fill(CGRect(origin: .zero, size: size))
        // Tip occupies upper 38% with a soft edge
        let tipHeight = size.height * 0.38
        cg.setFillColor(tipColor.cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: size.width, height: tipHeight))
        // Soft seam: a slight gradient at the boundary
        let seam = CGRect(x: 0, y: tipHeight - 6, width: size.width, height: 14)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [tipColor.cgColor, base.cgColor] as CFArray,
            locations: [0, 1]
        ) {
            cg.saveGState()
            cg.clip(to: seam)
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: seam.minY),
                end: CGPoint(x: 0, y: seam.maxY),
                options: []
            )
            cg.restoreGState()
        }
    }

    private static func drawPinkGlitter(in cg: CGContext, size: CGSize) {
        drawVerticalGradient(in: cg, size: size, colors: [
            UIColor(red: 0.98, green: 0.42, blue: 0.68, alpha: 1),
            UIColor(red: 0.85, green: 0.20, blue: 0.45, alpha: 1)
        ])
        // Sparkles — small light dots scattered. Use cream colors so they
        // pass the texture mapper's white-keying threshold (must be < 240
        // on at least one channel).
        var rng = SystemRandomNumberGenerator()
        let sparkleColors: [UIColor] = [
            UIColor(red: 1.0, green: 0.92, blue: 0.96, alpha: 0.92),
            UIColor(red: 1.0, green: 0.85, blue: 0.92, alpha: 0.85),
            UIColor(red: 0.98, green: 0.78, blue: 0.85, alpha: 0.95)
        ]
        for _ in 0..<140 {
            let x = CGFloat(UInt32.random(in: 0..<UInt32(size.width), using: &rng))
            let y = CGFloat(UInt32.random(in: 0..<UInt32(size.height), using: &rng))
            let r = CGFloat.random(in: 1.0...3.4, using: &rng)
            let color = sparkleColors[Int.random(in: 0..<sparkleColors.count, using: &rng)]
            cg.setFillColor(color.cgColor)
            cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
    }

    private static func drawOceanBlue(in cg: CGContext, size: CGSize) {
        drawVerticalGradient(in: cg, size: size, colors: [
            UIColor(red: 0.30, green: 0.78, blue: 0.95, alpha: 1),
            UIColor(red: 0.06, green: 0.20, blue: 0.55, alpha: 1)
        ])
    }

    private static func drawGoldMirror(in cg: CGContext, size: CGSize) {
        // Multi-stop gold that suggests metallic reflection
        drawVerticalGradient(in: cg, size: size, colors: [
            UIColor(red: 0.99, green: 0.92, blue: 0.55, alpha: 1),
            UIColor(red: 0.84, green: 0.60, blue: 0.18, alpha: 1),
            UIColor(red: 0.99, green: 0.88, blue: 0.50, alpha: 1),
            UIColor(red: 0.62, green: 0.40, blue: 0.10, alpha: 1)
        ], locations: [0.0, 0.35, 0.55, 1.0])
    }

    private static func drawRoyalPurple(in cg: CGContext, size: CGSize) {
        drawVerticalGradient(in: cg, size: size, colors: [
            UIColor(red: 0.78, green: 0.42, blue: 0.95, alpha: 1),
            UIColor(red: 0.36, green: 0.10, blue: 0.55, alpha: 1)
        ])
    }

    // MARK: - Helpers

    private static func drawVerticalGradient(
        in cg: CGContext,
        size: CGSize,
        colors: [UIColor],
        locations: [CGFloat]? = nil
    ) {
        let cgColors = colors.map { $0.cgColor } as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: cgColors,
            locations: locations
        ) else { return }
        cg.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: size.height),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    private static func drawGloss(in cg: CGContext, size: CGSize) {
        // Soft white-ish highlight ellipse at the tip area.
        let glossHeight = size.height * 0.35
        let glossRect = CGRect(
            x: -size.width * 0.1,
            y: 4,
            width: size.width * 1.2,
            height: glossHeight
        )
        cg.saveGState()
        let colors = [
            UIColor.white.withAlphaComponent(0.30).cgColor,
            UIColor.white.withAlphaComponent(0.0).cgColor
        ] as CFArray
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 1]
        ) {
            cg.addEllipse(in: glossRect)
            cg.clip()
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: glossRect.minY),
                end: CGPoint(x: 0, y: glossRect.maxY),
                options: []
            )
        }
        cg.restoreGState()
    }
}
