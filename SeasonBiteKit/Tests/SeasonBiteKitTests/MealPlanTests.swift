import Foundation
import XCTest
@testable import SeasonBiteKit

final class MealPlanTests: XCTestCase {
    /// The hand-written sample in the repo's examples/ folder.
    private func loadSample() throws -> MealPlan {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SeasonBiteKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // SeasonBiteKit
            .deletingLastPathComponent() // repo root
        let url = repoRoot.appendingPathComponent("examples/2026-10-01_family_dinner.json")
        return try MealPlan.decode(from: Data(contentsOf: url))
    }

    func testSampleDecodes() throws {
        let plan = try loadSample()
        XCTAssertEqual(plan.dishes.count, 4)
        XCTAssertEqual(plan.household.children.first?.ageYears, 4)

        let tofu = try XCTUnwrap(plan.dishes.first { $0.id == "golden_sour_tofu_caltrop" })
        XCTAssertEqual(tofu.flavorPillar, .mildSichuanHunan)
        XCTAssertEqual(tofu.dualPrep.splitPoint, 3)
        XCTAssertEqual(tofu.steps[3].portion, .adultOnly)
        XCTAssertTrue(tofu.ingredients.contains { $0.role == .adultHeat })
    }

    func testSamplePassesRules() throws {
        XCTAssertEqual(MealPlanRules.violations(in: try loadSample()), [])
    }

    func testAdultHeatBeforeChildPortionIsRejected() throws {
        var plan = try loadSample()
        let index = try XCTUnwrap(plan.dishes.firstIndex { $0.id == "golden_sour_tofu_caltrop" })
        plan.dishes[index].steps[1].portion = .adultOnly

        let errors = MealPlanRules.violations(in: plan)
        XCTAssertTrue(errors.contains { $0.contains("adult-only step 2 comes before") }, "\(errors)")
    }

    func testSichuanHunanWithoutDualPrepIsRejected() throws {
        var plan = try loadSample()
        let index = try XCTUnwrap(plan.dishes.firstIndex { $0.id == "golden_sour_tofu_caltrop" })
        plan.dishes[index].dualPrep = DualPrep(applies: false, splitPoint: nil, adultFinish: nil)

        let errors = MealPlanRules.violations(in: plan)
        XCTAssertTrue(errors.contains { $0.contains("must use dual-prep") }, "\(errors)")
        XCTAssertTrue(errors.contains { $0.contains("adult-only heat but dual-prep is off") }, "\(errors)")
    }

    func testSpicyChildPortionIsRejected() throws {
        var plan = try loadSample()
        plan.dishes[0].childSafety.nonSpicy = false
        XCTAssertFalse(MealPlanRules.violations(in: plan).isEmpty)
    }

    func testGoldenPlateOutOfRangeIsRejected() throws {
        var plan = try loadSample()
        plan.goldenPlate = GoldenPlate(vegTuberPct: 35, proteinPct: 35, complexCarbPct: 30)
        let errors = MealPlanRules.violations(in: plan)
        XCTAssertTrue(errors.contains { $0.contains("veg/tuber") }, "\(errors)")
        XCTAssertTrue(errors.contains { $0.contains("protein") }, "\(errors)")
    }

    func testChildSodiumCapDependsOnAge() throws {
        var plan = try loadSample()
        XCTAssertEqual(MealPlanRules.violations(in: plan), [])

        plan.household.children = [Child(ageYears: 2, allergies: [])]
        let errors = MealPlanRules.violations(in: plan)
        XCTAssertTrue(errors.contains { $0.contains("exceeds 300") }, "\(errors)")
    }
}
