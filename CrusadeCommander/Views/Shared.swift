import SwiftUI

// MARK: - Theme

extension Color {
    static let bg = Color(red: 0.04, green: 0.04, blue: 0.05)
    static let bgCard = Color(red: 0.086, green: 0.086, blue: 0.098)
    static let bgElevated = Color(red: 0.122, green: 0.122, blue: 0.141)
    static let ink = Color(red: 0.91, green: 0.90, blue: 0.89)
    static let inkDim = Color(red: 0.64, green: 0.62, blue: 0.60)
    static let inkFade = Color(red: 0.42, green: 0.41, blue: 0.38)
    static let accent = Color(red: 0.85, green: 0.46, blue: 0.02)
    static let accentSoft = Color(red: 0.85, green: 0.46, blue: 0.02).opacity(0.15)
    static let dangerC = Color(red: 0.86, green: 0.15, blue: 0.15)
    static let successC = Color(red: 0.09, green: 0.64, blue: 0.29)
    static let warningC = Color(red: 0.92, green: 0.70, blue: 0.03)
}

// MARK: - Components

struct BadgeView: View {
    enum Style { case accent, success, danger, warning, dim }
    let text: String
    var style: Style = .dim

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(Capsule())
    }
    private var bg: Color {
        switch style {
        case .accent: return Color.accentSoft
        case .success: return Color.successC.opacity(0.15)
        case .danger: return Color.dangerC.opacity(0.15)
        case .warning: return Color.warningC.opacity(0.15)
        case .dim: return Color.white.opacity(0.05)
        }
    }
    private var fg: Color {
        switch style {
        case .accent: return .accent
        case .success: return .successC
        case .danger: return .dangerC
        case .warning: return .warningC
        case .dim: return .inkDim
        }
    }
}

struct CardBox<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .background(Color.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(enabled ? Color.accent : Color.bgElevated)
            .foregroundStyle(enabled ? Color.white : Color.inkFade)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.bgElevated)
            .foregroundStyle(Color.ink)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(Color.dangerC)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dangerC.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 10) {
            Text(icon).font(.system(size: 36)).foregroundStyle(Color.inkFade)
            Text(title).font(.headline).foregroundStyle(Color.inkDim)
            Text(subtitle).font(.caption).foregroundStyle(Color.inkFade).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Faction & team suggestions (subset)

let warhammerFactions = [
    "Space Marines", "Blood Angels", "Dark Angels", "Space Wolves", "Ultramarines",
    "Imperial Fists", "Salamanders", "Iron Hands", "Raven Guard", "White Scars",
    "Grey Knights", "Deathwatch", "Adeptus Custodes", "Sisters of Battle",
    "Astra Militarum", "Adeptus Mechanicus", "Imperial Knights",
    "Chaos Space Marines", "Death Guard", "Thousand Sons", "World Eaters",
    "Emperor's Children", "Chaos Knights", "Daemons of Chaos",
    "Necrons", "Orks", "T'au Empire", "Tyranids", "Genestealer Cults",
    "Drukhari", "Craftworld Aeldari", "Harlequins", "Leagues of Votann",
]

let suggestedTeams = ["Imperium", "Chaos", "Xenos", "Forces of Order", "Forces of Disorder"]

let playerColors: [String] = [
    "#C0392B", "#E74C3C", "#E67E22", "#F39C12",
    "#27AE60", "#2ECC71", "#2980B9", "#3498DB",
    "#8E44AD", "#9B59B6", "#16A085", "#1ABC9C",
    "#F1C40F", "#D35400", "#7F8C8D", "#BDC3C7",
]

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        let i = UInt64(s, radix: 16) ?? 0
        let r, g, b: UInt64
        if s.count == 6 {
            r = (i >> 16) & 0xff; g = (i >> 8) & 0xff; b = i & 0xff
        } else {
            r = 128; g = 128; b = 128
        }
        self.init(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
    }
}

struct ColorPickerStrip: View {
    @Binding var selection: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(playerColors, id: \.self) { hex in
                    Button(action: { selection = hex }) {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(selection == hex ? Color.white : Color.clear, lineWidth: 2))
                    }
                }
            }.padding(.vertical, 2)
        }
    }
}
