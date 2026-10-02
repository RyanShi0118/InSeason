import Foundation

/// The SeasonBite safety and nutrition rules, checked on a decoded plan.
/// Model output must pass these before the app shows it.
public enum MealPlanRules {
    /// Child sodium cap for the whole meal, by age.
    public static func childSodiumCapMg(ageYears: Double) -> Double? {
        if ageYears < 4 { return 300 }
        if ageYears < 9 { return 500 }
        return nil
    }

    public static func violations(in plan: MealPlan) -> [String] {
        var errors: [String] = []

        let plate = plan.goldenPlate
        let target = GoldenPlate.target
        let tolerance = GoldenPlate.tolerance
        for (name, actual, goal) in [
            ("veg/tuber", plate.vegTuberPct, target.vegTuberPct),
            ("protein", plate.proteinPct, target.proteinPct),
            ("complex carb", plate.complexCarbPct, target.complexCarbPct),
        ] where abs(actual - goal) > tolerance {
            errors.append("Golden Plate \(name) is \(actual)%, target \(goal)% ± \(tolerance)")
        }
        let total = plate.vegTuberPct + plate.proteinPct + plate.complexCarbPct
        if abs(total - 100) > 1 {
            errors.append("Golden Plate adds up to \(total)%, not 100%")
        }

        for dish in plan.dishes {
            errors += violations(in: dish)
        }

        let childSodium = plan.dishes.reduce(0) { $0 + $1.childSafety.sodiumMgPerChildServing }
        for child in plan.household.children {
            if let cap = childSodiumCapMg(ageYears: child.ageYears), childSodium > cap {
                errors.append("Child sodium \(childSodium) mg exceeds \(cap) mg for age \(child.ageYears)")
            }
        }

        let dishIDs = Set(plan.dishes.map(\.id))
        let sources = plan.nutrition.childMicronutrientSources
        for (nutrient, ids) in [("calcium", sources.calcium), ("iron", sources.iron), ("zinc", sources.zinc), ("dha", sources.dha)] {
            if ids.isEmpty {
                errors.append("No dish supplies \(nutrient) for the child")
            }
            for id in ids where !dishIDs.contains(id) {
                errors.append("\(nutrient) source names unknown dish \(id)")
            }
        }

        if !plan.nutrition.isEstimate {
            errors.append("Nutrition must be marked as an estimate")
        }

        return errors
    }

    public static func violations(in dish: Dish) -> [String] {
        var errors: [String] = []
        let id = dish.id

        if !dish.childSafety.nonSpicy {
            errors.append("\(id): child portion must be non-spicy")
        }

        let numbers = dish.steps.map(\.n)
        if numbers != Array(stride(from: 1, through: dish.steps.count, by: 1)) {
            errors.append("\(id): steps must be numbered 1 to \(dish.steps.count)")
        }

        let hasHeat = dish.ingredients.contains { $0.role == .adultHeat }
        if dish.flavorPillar == .mildSichuanHunan && !dish.dualPrep.applies {
            errors.append("\(id): mild Sichuan-Hunan dishes must use dual-prep")
        }
        if hasHeat && !dish.dualPrep.applies {
            errors.append("\(id): has adult-only heat but dual-prep is off")
        }

        guard dish.dualPrep.applies else { return errors }

        guard let split = dish.dualPrep.splitPoint else {
            errors.append("\(id): dual-prep needs a split point")
            return errors
        }
        if dish.dualPrep.adultFinish?.isEmpty ?? true {
            errors.append("\(id): dual-prep needs an adult finish")
        }
        guard let splitStep = dish.steps.first(where: { $0.n == split }), splitStep.portion == .childOnly else {
            errors.append("\(id): split point \(split) must be a child-only step")
            return errors
        }
        for step in dish.steps {
            if step.portion == .adultOnly && step.n <= split {
                errors.append("\(id): adult-only step \(step.n) comes before the child portion is plated")
            }
            if step.portion == .shared && step.n > split {
                errors.append("\(id): shared step \(step.n) comes after the child portion is plated")
            }
        }
        return errors
    }
}
