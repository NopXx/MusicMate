//
//  TextToShape.swift
//  MusicMate
//
//  Created by NopXx on 7/5/2569 BE.
//

import SwiftUI
import CoreText

#if canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
#elseif canImport(AppKit)
import AppKit
typealias PlatformFont = NSFont
#endif

enum GlassTextVariant: String, CaseIterable, Identifiable {
    case regular
    case clear
    case tinted
    case interactive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .regular: return "Regular"
        case .clear: return "Clear"
        case .tinted: return "Tinted"
        case .interactive: return "Interactive"
        }
    }
}

struct GlassEffectText: View {
    var text: String
    var font: PlatformFont
    var fallbackColor: Color = .primary
    var variant: GlassTextVariant = .regular
    var glassTint: Color = .clear

    var body: some View {
        let textShape = TextToShape(
            value: text,
            fontName: font.fontName,
            fontSize: font.pointSize
        )

        Text(text)
            .font(.custom(font.fontName, size: font.pointSize))
            .opacity(0)
            .glassEffect(resolvedGlass(), in: textShape)
    }

    private func resolvedGlass() -> Glass {
        let base: Glass
        switch variant {
        case .regular:     base = .regular
        case .clear:       base = .clear
        case .tinted:      base = .regular.tint(glassTint == .clear ? .white.opacity(0.7) : glassTint)
        case .interactive: base = .regular.interactive()
        }
        if variant != .tinted, glassTint != .clear {
            return base.tint(glassTint)
        }
        return base
    }
}

struct TextToShape: Shape {
    var value: String
    var fontName: String
    var fontSize: CGFloat
    
    nonisolated func path(in rect: CGRect) -> Path {
        let ctFont = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        var path = Path()
        drawGlyphs(value, ctFont: ctFont) { (position, glyphPath) in
            let transform = CGAffineTransform(translationX: position.x, y: position.y).scaledBy(x: 1, y: -1)
            let newPath = Path(glyphPath).applying(transform)
            
            path.addPath(newPath)
        }
        
        let bounds = path.boundingRect
        let offsetX = rect.minX - bounds.minX
        let offsetY = rect.minY - bounds.minY
        let centerTransform = CGAffineTransform(translationX: offsetX, y: offsetY)
        
        return path.applying(centerTransform)
    }
}

nonisolated
private func drawGlyphs(
    _ value: String,
    ctFont: CTFont,
    draw: @escaping (_ position: CGPoint, _ glyphPath: CGPath) -> Void
) {
    let attributedString = NSAttributedString(
        string: value,
        attributes: [NSAttributedString.Key(kCTFontAttributeName as String): ctFont]
    )

    let line = CTLineCreateWithAttributedString(attributedString)
    let runs = CTLineGetGlyphRuns(line)

    for runIndex in 0..<CFArrayGetCount(runs) {
        let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, runIndex), to: CTRun.self)
        let runCount = CTRunGetGlyphCount(run)

        for index in 0..<runCount {
            let glyphRange = CFRangeMake(index, 1)
            var glyph = CGGlyph()
            var position = CGPoint()

            CTRunGetGlyphs(run, glyphRange, &glyph)
            CTRunGetPositions(run, glyphRange, &position)

            if let glyphPath = CTFontCreatePathForGlyph(ctFont, glyph, nil) {
                draw(position, glyphPath)
            }
        }
    }
}
