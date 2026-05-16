import SwiftUI

struct MarqueeText: View {
    let text: String
    let font: Font
    var color: Color = .white
    var spacing: CGFloat = 36
    var pixelsPerSecond: CGFloat = 28
    var startDelay: Double = 1.2

    @State private var textSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let containerW = geo.size.width
            let needScroll = textSize.width > containerW + 1

            ZStack(alignment: .leading) {
                if needScroll {
                    scrollingContent(containerW: containerW)
                } else {
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .lineLimit(1)
                }
            }
            .frame(width: containerW,
                   height: textSize.height > 0 ? textSize.height : nil,
                   alignment: .leading)
            .clipped()
        }
        .frame(height: textSize.height > 0 ? textSize.height : nil)
        .background(measurement)
        .id(text)
    }

    @ViewBuilder
    private func scrollingContent(containerW: CGFloat) -> some View {
        let loopWidth = textSize.width + spacing
        let duration = max(Double(loopWidth) / Double(pixelsPerSecond), 0.1)
        let cycle = duration + startDelay

        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phaseT = t.truncatingRemainder(dividingBy: cycle)
            let progress = max(0, min(1, (phaseT - startDelay) / duration))
            let offset = CGFloat(progress) * loopWidth

            HStack(spacing: spacing) {
                Text(text).font(font).foregroundStyle(color).fixedSize()
                Text(text).font(font).foregroundStyle(color).fixedSize()
            }
            .offset(x: -offset)
        }
    }

    private var measurement: some View {
        Text(text)
            .font(font)
            .fixedSize()
            .hidden()
            .background(
                GeometryReader { g in
                    Color.clear
                        .preference(key: TextSizeKey.self, value: g.size)
                }
            )
            .onPreferenceChange(TextSizeKey.self) { textSize = $0 }
    }
}

private struct TextSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
