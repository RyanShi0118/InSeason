import SeasonBiteKit
import SwiftUI

extension FlavorPillar {
    var color: Color {
        switch self {
        case .jiangnanOriginal: return .teal
        case .cantoneseNourishing: return .orange
        case .mildSichuanHunan: return .red
        }
    }

    var symbol: String {
        switch self {
        case .jiangnanOriginal: return "leaf"
        case .cantoneseNourishing: return "cup.and.saucer"
        case .mildSichuanHunan: return "flame"
        }
    }
}

extension Step.Portion {
    var label: String {
        switch self {
        case .shared: return "全家 · Everyone"
        case .childOnly: return "孩子 · Child"
        case .adultOnly: return "大人 · Adults"
        }
    }

    var color: Color {
        switch self {
        case .shared: return .secondary
        case .childOnly: return .green
        case .adultOnly: return .red
        }
    }
}

/// Stand-in for the generated hero photo until image generation is wired up.
struct HeroPlaceholder: View {
    let pillar: FlavorPillar
    var height: CGFloat = 160

    var body: some View {
        LinearGradient(
            colors: [pillar.color.opacity(0.55), pillar.color.opacity(0.15)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: height)
        .overlay {
            Image(systemName: "fork.knife")
                .font(.system(size: height / 4))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

struct Badge: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

func formatAmount(_ amount: Double) -> String {
    amount.rounded() == amount ? String(Int(amount)) : String(format: "%.1f", amount)
}
