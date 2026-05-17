import SwiftUI

// MARK: - Design System: Colors

extension Color {
    // ── Backgrounds ──────────────────────────────────────────────
    /// Main app background (#141413)
    static let backgroundPrimary = Color(hex: "141413")
    /// Cards, sheets, secondary surfaces (#262624)
    static let backgroundSecondary = Color(hex: "262624")
    /// Elevated surfaces, modals (#323230)
    static let backgroundTertiary = Color(hex: "323230")

    // ── Labels ───────────────────────────────────────────────────
    /// Primary text (#FAF9F6) — warm white
    static let labelPrimary = Color(hex: "FAF9F6")
    /// Secondary text, subtitles (#87867F)
    static let labelSecondary = Color(hex: "87867F")
    /// Tertiary text, placeholders (#5C5B56)
    static let labelTertiary = Color(hex: "5C5B56")

    // ── Brand ────────────────────────────────────────────────────
    /// Primary brand — terracotta (#C96542)
    static let brandPrimary = Color(hex: "C96542")
    /// Lighter brand for hover/highlight (#D4845F)
    static let brandSecondary = Color(hex: "D4845F")
    /// Muted brand for subtle fills (#C96542, 15% opacity)
    static let brandMuted = Color(hex: "C96542").opacity(0.15)

    // ── Semantic ─────────────────────────────────────────────────
    /// Success — warm sage green (#7A9E6B)
    static let semanticSuccess = Color(hex: "7A9E6B")
    /// Error / destructive — warm clay red (#C44B3F)
    static let semanticError = Color(hex: "C44B3F")
    /// Warning — warm amber (#D4A03C)
    static let semanticWarning = Color(hex: "D4A03C")
    /// Info — warm teal (#5B8FA8)
    static let semanticInfo = Color(hex: "5B8FA8")

    // ── UI Elements ──────────────────────────────────────────────
    /// Chat bubble background (agent messages)
    static let bubbleBackground = Color(hex: "262624")
    /// Code block background
    static let markdownCodeBackground = Color(hex: "1E1E1C")
    /// Code block border
    static let markdownCodeBorder = Color(hex: "3A3A37")
    /// Prompt card border
    static let promptCardBorder = Color(hex: "3A3A37")
    /// Separator / divider
    static let separator = Color(hex: "3A3A37")
    /// Input field background
    static let inputBackground = Color(hex: "1E1E1C")

    // ── Legacy aliases (backward compatibility) ──────────────────
    static let appBackground = backgroundPrimary
    static let appSecondaryBackground = backgroundSecondary
}

// MARK: - Design System: Typography

extension Font {
    // ── Heading fonts: .serif + .bold ────────────────────────────
    /// Large Title — 34pt Serif Bold
    static let dsLargeTitle = Font.system(.largeTitle, design: .serif).bold()
    /// Title 1 — 28pt Serif Bold
    static let dsTitle = Font.system(.title, design: .serif).bold()
    /// Title 2 — 22pt Serif Bold
    static let dsTitle2 = Font.system(.title2, design: .serif).bold()
    /// Title 3 — 20pt Serif Bold
    static let dsTitle3 = Font.system(.title3, design: .serif).bold()
    /// Headline — 17pt SF Pro Bold (buttons, action labels)
    static let dsHeadline = Font.system(.headline, design: .default).bold()

    // ── Body fonts: system default ──────────────────────────────
    /// Body — 17pt
    static let dsBody = Font.body
    /// Callout — 16pt
    static let dsCallout = Font.callout
    /// Subheadline — 15pt
    static let dsSubheadline = Font.subheadline
    /// Footnote — 13pt
    static let dsFootnote = Font.footnote
    /// Caption — 12pt
    static let dsCaption = Font.caption
    /// Caption 2 — 11pt
    static let dsCaption2 = Font.caption2
}

// MARK: - View Modifiers

extension View {
    /// Apply heading style: serif bold + primary label color.
    func headingStyle(_ font: Font = .dsTitle) -> some View {
        self.font(font).foregroundColor(.labelPrimary)
    }

    /// Apply body style: default font + primary label color.
    func bodyStyle() -> some View {
        self.font(.dsBody).foregroundColor(.labelPrimary)
    }

    /// Apply secondary text style.
    func secondaryStyle() -> some View {
        self.font(.dsSubheadline).foregroundColor(.labelSecondary)
    }
}

// MARK: - Color Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
