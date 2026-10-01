import Foundation
import SeasonBiteKit

enum MealPlanLoader {
    enum LoadError: LocalizedError {
        case missingResource(String)
        case failsRules([String])

        var errorDescription: String? {
            switch self {
            case .missingResource(let name):
                return "Missing bundled meal plan \(name).json"
            case .failsRules(let errors):
                return "Meal plan breaks SeasonBite rules:\n" + errors.joined(separator: "\n")
            }
        }
    }

    /// Loads the bundled sample. Later this will come from the recipe engine.
    static func loadSample(named name: String = "2026-10-01_family_dinner") throws -> MealPlan {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw LoadError.missingResource(name)
        }
        let plan = try MealPlan.decode(from: Data(contentsOf: url))
        let errors = MealPlanRules.violations(in: plan)
        guard errors.isEmpty else { throw LoadError.failsRules(errors) }
        return plan
    }
}
