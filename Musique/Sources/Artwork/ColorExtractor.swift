import AppKit
import CoreImage

struct ArtworkPalette {
    var accent: NSColor
    var gradientStart: NSColor
    var gradientMid: NSColor
    var gradientEnd: NSColor

    static let `default` = ArtworkPalette(
        accent: NSColor(red: 0.98, green: 0.18, blue: 0.28, alpha: 1),
        gradientStart: NSColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1),
        gradientMid: NSColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1),
        gradientEnd: NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)
    )
}

actor ColorExtractor {
    static let shared = ColorExtractor()
    private var cache: [String: ArtworkPalette] = [:]

    func palette(for url: String) async -> ArtworkPalette {
        if let cached = cache[url] { return cached }
        guard let imgURL = URL(string: url) else { return .default }
        do {
            let (data, _) = try await URLSession.shared.data(from: imgURL)
            guard let image = NSImage(data: data) else { return .default }
            let palette = Self.extract(from: image)
            cache[url] = palette
            return palette
        } catch {
            return .default
        }
    }

    private static func extract(from image: NSImage) -> ArtworkPalette {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .default
        }
        let target: CGFloat = 64
        let width = Int(target)
        let height = Int(target)
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &pixels, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: space, bitmapInfo: info) else { return .default }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: target, height: target))

        var rTotal = 0, gTotal = 0, bTotal = 0
        var saturatedR = 0, saturatedG = 0, saturatedB = 0, saturatedCount = 0
        let pixelCount = width * height
        for i in 0..<pixelCount {
            let idx = i * 4
            let r = Int(pixels[idx])
            let g = Int(pixels[idx + 1])
            let b = Int(pixels[idx + 2])
            rTotal += r; gTotal += g; bTotal += b

            let mx = max(r, g, b), mn = min(r, g, b)
            let sat = mx == 0 ? 0 : (mx - mn) * 100 / mx
            let lum = (r * 299 + g * 587 + b * 114) / 1000
            if sat > 35 && lum > 60 && lum < 220 {
                saturatedR += r; saturatedG += g; saturatedB += b; saturatedCount += 1
            }
        }

        let avgR = CGFloat(rTotal / pixelCount) / 255
        let avgG = CGFloat(gTotal / pixelCount) / 255
        let avgB = CGFloat(bTotal / pixelCount) / 255

        let accent: NSColor
        if saturatedCount > 0 {
            accent = NSColor(
                red: CGFloat(saturatedR / saturatedCount) / 255,
                green: CGFloat(saturatedG / saturatedCount) / 255,
                blue: CGFloat(saturatedB / saturatedCount) / 255,
                alpha: 1)
        } else {
            accent = NSColor(red: avgR, green: avgG, blue: avgB, alpha: 1)
        }

        return ArtworkPalette(
            accent: accent,
            gradientStart: NSColor(red: avgR * 1.05, green: avgG * 1.05, blue: avgB * 1.05, alpha: 1),
            gradientMid: NSColor(red: avgR * 0.65, green: avgG * 0.65, blue: avgB * 0.65, alpha: 1),
            gradientEnd: NSColor(red: avgR * 0.35, green: avgG * 0.35, blue: avgB * 0.35, alpha: 1)
        )
    }
}
