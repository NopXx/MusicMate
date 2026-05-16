import SwiftUI

// MARK: - Design tokens

enum SettingsTokens {
    enum Radius {
        static let card: CGFloat = 14
        static let tile: CGFloat = 7
        static let pill: CGFloat = 999
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
    }

    static let cardFill: Color = Color(nsColor: .controlBackgroundColor)
    static let cardStroke: Color = Color.primary.opacity(0.07)
    static let cardShadow: Color = Color.black.opacity(0.05)

    static let pageBackground: Color = Color(nsColor: .windowBackgroundColor)
}

// MARK: - Card container

struct SettingsCard<Content: View>: View {
    let icon: String
    let iconTint: Color
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Spacing.md) {
            HStack(alignment: .center, spacing: 12) {
                TintedIconTile(icon: icon, tint: iconTint, size: 30, corner: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if let trailing { trailing }
            }

            VStack(alignment: .leading, spacing: SettingsTokens.Spacing.md) {
                content()
            }
        }
        .padding(SettingsTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsTokens.Radius.card, style: .continuous)
                .fill(SettingsTokens.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsTokens.Radius.card, style: .continuous)
                .stroke(SettingsTokens.cardStroke, lineWidth: 0.5)
        )
        .shadow(color: SettingsTokens.cardShadow, radius: 6, x: 0, y: 2)
    }
}

extension SettingsCard {
    init(icon: String,
         iconTint: Color,
         title: LocalizedStringKey,
         subtitle: LocalizedStringKey? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.trailing = nil
        self.content = content
    }
}

// MARK: - Tinted icon tile

struct TintedIconTile: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 22
    var corner: CGFloat = SettingsTokens.Radius.tile

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [tint, tint.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: tint.opacity(0.25), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Sidebar tile (smaller, no shadow — list rows are dense)

struct SidebarTile: View {
    let icon: String
    let tint: Color

    var body: some View {
        TintedIconTile(icon: icon, tint: tint, size: 22, corner: 6)
    }
}

// MARK: - Status badge

enum BadgeTone {
    case success, danger, neutral, info, warning

    var gradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .success: colors = [.green, Color(red: 0.2, green: 0.75, blue: 0.55)]
        case .danger:  colors = [.red, .orange]
        case .neutral: colors = [Color.gray.opacity(0.65), Color.gray.opacity(0.45)]
        case .info:    colors = [.blue, .cyan]
        case .warning: colors = [.orange, .yellow]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}

struct StatusBadge: View {
    let text: String
    let tone: BadgeTone

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous).fill(tone.gradient)
            )
            .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Card row

struct CardRow<Trailing: View>: View {
    let label: LocalizedStringKey
    var help: LocalizedStringKey? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.subheadline)
                if let help {
                    Text(help).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

// MARK: - Right-aligned toggle row

struct SettingsToggleRow: View {
    let label: LocalizedStringKey
    var help: LocalizedStringKey? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.subheadline)
                if let help {
                    Text(help).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

// MARK: - Numeric input field (TextField + tiny stepper, step 1)

struct SettingsNumberField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var width: CGFloat = 60
    var suffix: String? = nil
    var onCommit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: width)
                .onChange(of: value) { _, new in
                    let clamped = min(max(new, range.lowerBound), range.upperBound)
                    if clamped != new { value = clamped }
                    onCommit?()
                }
            if let suffix {
                Text(suffix)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, alignment: .leading)
            }
            Stepper("", value: $value, in: range, step: 1)
                .labelsHidden()
        }
    }
}

// MARK: - Footer text

struct CardFooter: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Primary gradient button style

struct PrimaryGradientButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: tint.opacity(0.35), radius: 4, x: 0, y: 2)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Tab page scaffold

struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsTokens.Spacing.md) {
                content()
            }
            .padding(SettingsTokens.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(SettingsTokens.pageBackground)
    }
}
