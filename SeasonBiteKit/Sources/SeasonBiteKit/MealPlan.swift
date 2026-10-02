import Foundation

/// One family meal, as produced by the recipe engine.
/// Mirrors `schema/meal_plan.schema.json`; JSON keys are snake_case.
public struct MealPlan: Codable, Hashable, Sendable {
    public var date: String
    public var region: String
    public var seasonNote: String
    public var household: Household
    public var goldenPlate: GoldenPlate
    public var dishes: [Dish]
    public var nutrition: Nutrition

    public static func decode(from data: Data) throws -> MealPlan {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(MealPlan.self, from: data)
    }

    /// snake_case JSON, the same shape the schema describes.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

public struct Household: Codable, Hashable, Sendable {
    public var adults: Int
    public var children: [Child]

    public init(adults: Int, children: [Child]) {
        self.adults = adults
        self.children = children
    }
}

public struct Child: Codable, Hashable, Sendable {
    public var ageYears: Double
    public var allergies: [String]?

    public init(ageYears: Double, allergies: [String]? = nil) {
        self.ageYears = ageYears
        self.allergies = allergies
    }
}

/// Share of the meal by weight. Targets are 50 / 25 / 25.
public struct GoldenPlate: Codable, Hashable, Sendable {
    public var vegTuberPct: Double
    public var proteinPct: Double
    public var complexCarbPct: Double

    public static let target = GoldenPlate(vegTuberPct: 50, proteinPct: 25, complexCarbPct: 25)
    public static let tolerance: Double = 5

    public init(vegTuberPct: Double, proteinPct: Double, complexCarbPct: Double) {
        self.vegTuberPct = vegTuberPct
        self.proteinPct = proteinPct
        self.complexCarbPct = complexCarbPct
    }
}

public enum FlavorPillar: String, Codable, CaseIterable, Sendable {
    case jiangnanOriginal = "jiangnan_original"
    case cantoneseNourishing = "cantonese_nourishing"
    case mildSichuanHunan = "mild_sichuan_hunan"

    public var nameZh: String {
        switch self {
        case .jiangnanOriginal: "江南本味"
        case .cantoneseNourishing: "广式温润"
        case .mildSichuanHunan: "轻川湘风味"
        }
    }

    public var nameEn: String {
        switch self {
        case .jiangnanOriginal: "Jiangnan Original"
        case .cantoneseNourishing: "Cantonese Gentle & Nourishing"
        case .mildSichuanHunan: "Mild Sichuan-Hunan"
        }
    }
}

public enum PlateRole: String, Codable, Sendable {
    case vegTuber = "veg_tuber"
    case protein
    case complexCarb = "complex_carb"
}

public struct Dish: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var nameZh: String
    public var nameEn: String
    public var flavorPillar: FlavorPillar
    public var techniques: [String]
    public var plateRole: [PlateRole]
    public var seasonalIngredients: [SeasonalIngredient]
    public var ingredients: [Ingredient]
    public var steps: [Step]
    public var dualPrep: DualPrep
    public var childSafety: ChildSafety
    public var heroImagePrompt: String

    public var totalMinutes: Double {
        steps.reduce(0) { $0 + $1.durationMin }
    }
}

public struct SeasonalIngredient: Codable, Hashable, Identifiable, Sendable {
    public var nameZh: String
    public var nameEn: String
    public var peakReason: String
    public var source: String

    public var id: String { nameZh }
}

public struct Ingredient: Codable, Hashable, Identifiable, Sendable {
    public enum Unit: String, Codable, Sendable {
        case g, ml, piece
    }

    public enum Role: String, Codable, Sendable {
        case vegTuber = "veg_tuber"
        case protein
        case complexCarb = "complex_carb"
        case aromatic
        case fat
        case seasoning
        case adultHeat = "adult_heat"
    }

    public var itemZh: String
    public var itemEn: String
    public var amount: Double
    public var unit: Unit
    public var role: Role

    public var id: String { itemZh }
}

public struct Step: Codable, Hashable, Identifiable, Sendable {
    public enum Portion: String, Codable, Sendable {
        case shared
        case childOnly = "child_only"
        case adultOnly = "adult_only"
    }

    public var n: Int
    public var textZh: String
    public var textEn: String
    public var durationMin: Double
    public var portion: Portion
    public var stepImagePrompt: String

    public var id: Int { n }
}

public struct DualPrep: Codable, Hashable, Sendable {
    public var applies: Bool
    /// Step number where the child portion is plated.
    public var splitPoint: Int?
    public var adultFinish: String?
}

public struct ChildSafety: Codable, Hashable, Sendable {
    public var nonSpicy: Bool
    public var boneFreeMethod: String
    public var sodiumMgPerChildServing: Double
    public var allergens: [String]
}

public struct Nutrition: Codable, Hashable, Sendable {
    public var isEstimate: Bool
    public var perAdult: Nutrients
    public var perChild: Nutrients
    public var childMicronutrientSources: MicronutrientSources
}

public struct Nutrients: Codable, Hashable, Sendable {
    public var kcal: Double
    public var proteinG: Double
    public var fiberG: Double
    public var satFatG: Double
    public var sodiumMg: Double
    public var calciumMg: Double?
    public var ironMg: Double?
    public var zincMg: Double?
    public var dhaMg: Double?
}

/// Which dishes (by id) supply each key child nutrient.
public struct MicronutrientSources: Codable, Hashable, Sendable {
    public var calcium: [String]
    public var iron: [String]
    public var zinc: [String]
    public var dha: [String]
}
