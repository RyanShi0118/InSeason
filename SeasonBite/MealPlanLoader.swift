import Foundation
import SeasonBiteKit

enum MealPlanLoader {
    enum LoadError: LocalizedError {
        case missingResource(String)
        case failsRules([String])

        var errorDescription: String? {
            switch self {
            case .missingResource(let name):
                return "Missing bundled file \(name)"
            case .failsRules(let errors):
                return "Meal plan breaks SeasonBite rules:\n" + errors.joined(separator: "\n")
            }
        }
    }

    /// The bundled 1 October sample, shown until the first real plan exists.
    static func loadSample(named name: String = "2026-10-01_family_dinner") throws -> MealPlan {
        let plan = try MealPlan.decode(from: bundled(name, "json"))
        let errors = MealPlanRules.violations(in: plan)
        guard errors.isEmpty else { throw LoadError.failsRules(errors) }
        return plan
    }

    /// The planner's system prompt, built from prompts/ and schema/ in the repo.
    static func systemPrompt() throws -> String {
        SystemPrompt.make(
            promptMarkdown: String(decoding: try bundled("seasonbite_chef_system", "md"), as: UTF8.self),
            schemaJSON: String(decoding: try bundled("meal_plan.schema", "json"), as: UTF8.self)
        )
    }

    private static func bundled(_ name: String, _ ext: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw LoadError.missingResource("\(name).\(ext)")
        }
        return try Data(contentsOf: url)
    }
}
