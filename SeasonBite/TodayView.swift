import SeasonBiteKit
import SwiftUI

struct TodayView: View {
    let plan: MealPlan

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                GoldenPlateBar(plate: plan.goldenPlate)
                ForEach(plan.dishes) { dish in
                    NavigationLink(value: dish) {
                        DishCard(dish: dish)
                    }
                    .buttonStyle(.plain)
                }
                NutritionSummary(nutrition: plan.nutrition, household: plan.household)
            }
            .padding()
        }
        .navigationTitle("知时食")
        .navigationDestination(for: Dish.self) { dish in
            DishDetailView(dish: dish)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayDate)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(plan.seasonNote)
                .font(.body)
            Text(householdText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var displayDate: String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: plan.date) else { return plan.date }
        return date.formatted(date: .complete, time: .omitted)
    }

    private var householdText: String {
        let ages = plan.household.children.map { "\(formatAmount($0.ageYears))y" }
        let kids = ages.isEmpty ? "" : " + child \(ages.joined(separator: ", "))"
        return "\(plan.household.adults) adults\(kids) · \(plan.region)"
    }
}

struct GoldenPlateBar: View {
    let plate: GoldenPlate

    private struct Segment: Identifiable {
        let name: String
        let pct: Double
        let color: Color
        var id: String { name }
    }

    private var segments: [Segment] {
        [
            Segment(name: "蔬菜 Veg", pct: plate.vegTuberPct, color: .green),
            Segment(name: "蛋白 Protein", pct: plate.proteinPct, color: .orange),
            Segment(name: "主食 Carbs", pct: plate.complexCarbPct, color: .brown),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Golden Plate")
                .font(.headline)
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(segments) { segment in
                        segment.color.frame(width: max(0, proxy.size.width * segment.pct / 100 - 2))
                    }
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())
            HStack {
                ForEach(segments) { segment in
                    Label("\(segment.name) \(formatAmount(segment.pct))%", systemImage: "circle.fill")
                        .labelStyle(DotLabelStyle(color: segment.color))
                    if segment.id != segments.last?.id { Spacer() }
                }
            }
            .font(.caption)
        }
    }
}

private struct DotLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            configuration.title
        }
    }
}

struct DishCard: View {
    let dish: Dish

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeroPlaceholder(pillar: dish.flavorPillar)
            VStack(alignment: .leading, spacing: 8) {
                Label(dish.flavorPillar.nameZh, systemImage: dish.flavorPillar.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(dish.flavorPillar.color)
                Text(dish.nameZh)
                    .font(.title3.weight(.semibold))
                Text(dish.nameEn)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Badge(text: "\(formatAmount(dish.totalMinutes.rounded(.up))) min", systemImage: "clock", color: .secondary)
                    Badge(text: "Kid-safe", systemImage: "checkmark.shield", color: .green)
                    if dish.dualPrep.applies {
                        Badge(text: "Dual-prep", systemImage: "arrow.triangle.branch", color: .red)
                    }
                }
            }
            .padding()
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct NutritionSummary: View {
    let nutrition: Nutrition
    let household: Household

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nutrition per person")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text("Adult").bold()
                    if !household.children.isEmpty { Text("Child").bold() }
                }
                row("Energy", \.kcal, "kcal")
                row("Protein", \.proteinG, "g")
                row("Fiber", \.fiberG, "g")
                row("Sat. fat", \.satFatG, "g")
                row("Sodium", \.sodiumMg, "mg")
            }
            .font(.subheadline)
            if nutrition.isEstimate {
                Text("Estimates, not lab values.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ name: String, _ key: KeyPath<Nutrients, Double>, _ unit: String) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary)
            Text("\(formatAmount(nutrition.perAdult[keyPath: key])) \(unit)")
            if !household.children.isEmpty {
                Text("\(formatAmount(nutrition.perChild[keyPath: key])) \(unit)")
            }
        }
    }
}
