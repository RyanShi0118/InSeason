import SeasonBiteKit
import SwiftUI

struct DishDetailView: View {
    let dish: Dish

    var body: some View {
        List {
            Section {
                HeroPlaceholder(pillar: dish.flavorPillar, height: 220)
                    .listRowInsets(EdgeInsets())
                VStack(alignment: .leading, spacing: 4) {
                    Text(dish.nameEn)
                        .font(.headline)
                    Text("\(dish.flavorPillar.nameZh) · \(dish.flavorPillar.nameEn)")
                        .font(.subheadline)
                        .foregroundStyle(dish.flavorPillar.color)
                    Text(dish.techniques.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("当季 In season") {
                ForEach(dish.seasonalIngredients) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.nameZh) \(item.nameEn)").font(.body.weight(.semibold))
                        Text(item.peakReason).font(.subheadline)
                        Label(item.source, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("食材 Ingredients") {
                ForEach(dish.ingredients) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.itemZh)
                            Text(item.itemEn).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if item.role == .adultHeat {
                            Badge(text: "Adults", systemImage: "flame", color: .red)
                        }
                        Text("\(formatAmount(item.amount)) \(item.unit.rawValue)")
                            .monospacedDigit()
                    }
                }
            }

            Section {
                ForEach(dish.steps) { step in
                    StepRow(step: step)
                    if dish.dualPrep.applies, step.n == dish.dualPrep.splitPoint {
                        Label("Child portion is plated. Heat goes in only after this.", systemImage: "checkmark.shield.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
            } header: {
                Text("做法 Steps")
            } footer: {
                if dish.dualPrep.applies, let finish = dish.dualPrep.adultFinish {
                    Text("Adult finish: \(finish)")
                }
            }

            Section("儿童安全 Child safety") {
                Label("Non-spicy", systemImage: "checkmark.circle")
                Label(dish.childSafety.boneFreeMethod, systemImage: "checkmark.circle")
                Label("Sodium ≈ \(formatAmount(dish.childSafety.sodiumMgPerChildServing)) mg per child serving", systemImage: "drop")
                if !dish.childSafety.allergens.isEmpty {
                    Label("Allergens: \(dish.childSafety.allergens.joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                DisclosureGroup("Photo prompts") {
                    Text(dish.heroImagePrompt).font(.caption)
                    ForEach(dish.steps) { step in
                        Text("\(step.n). \(step.stepImagePrompt)").font(.caption)
                    }
                }
            }
        }
        .navigationTitle(dish.nameZh)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StepRow: View {
    let step: Step

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(step.n)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(step.portion.color.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(step.textZh)
                Text(step.textEn).font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Text(step.portion.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(step.portion.color)
                    if step.durationMin > 0 {
                        Text("· \(formatAmount(step.durationMin)) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
