import Foundation
import Observation
import SeasonBiteKit

/// Today's plan and its photos. Plans come from DeepSeek, photos from Qwen; both are saved on the phone.
@MainActor
@Observable
final class MealStore {
    enum Phase: Equatable {
        case idle
        case planning
        case drawing(done: Int, total: Int)
    }

    private(set) var plan: MealPlan?
    private(set) var isSample = false
    private(set) var phase: Phase = .idle
    private(set) var images: [String: Data] = [:]
    var errorMessage: String?

    var isBusy: Bool { phase != .idle }

    private let directory: URL
    private var planURL: URL { directory.appendingPathComponent("current_plan.json") }
    private var imageDirectory: URL { directory.appendingPathComponent("images", isDirectory: true) }

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SeasonBite", isDirectory: true)
        try? FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        loadSaved()
    }

    static func heroKey(_ dish: Dish) -> String { "\(dish.id)-hero" }
    static func stepKey(_ dish: Dish, _ step: Step) -> String { "\(dish.id)-step-\(step.n)" }

    static func todayInShanghai(now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now)
    }

    // MARK: - Planning

    func planToday() async {
        guard !isBusy else { return }
        guard let key = Keychain.read(.deepseek) else {
            errorMessage = "Add your DeepSeek API key in Settings first."
            return
        }
        let settings = ProviderSettings.load()
        errorMessage = nil
        phase = .planning
        do {
            let planner = DeepSeekPlanner(
                apiKey: key,
                systemPrompt: try MealPlanLoader.systemPrompt(),
                model: settings.deepseekModel,
                baseURL: settings.deepseekBaseURL
            )
            let newPlan = try await planner.plan(date: Self.todayInShanghai(), household: settings.household)
            try replacePlan(with: newPlan)
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
            return
        }
        phase = .idle
        await drawDishPhotos()
    }

    // MARK: - Photos

    /// One square photo per dish, for the cards.
    func drawDishPhotos() async {
        guard let plan else { return }
        let jobs = plan.dishes
            .filter { images[Self.heroKey($0)] == nil }
            .map { (key: Self.heroKey($0), prompt: $0.heroImagePrompt, isStep: false) }
        await draw(jobs)
    }

    /// One 4:3 photo per step of a dish. Only on request, since a plan has a dozen or more steps.
    func drawStepPhotos(for dish: Dish) async {
        let jobs = dish.steps
            .filter { images[Self.stepKey(dish, $0)] == nil }
            .map { (key: Self.stepKey(dish, $0), prompt: $0.stepImagePrompt, isStep: true) }
        await draw(jobs)
    }

    private func draw(_ jobs: [(key: String, prompt: String, isStep: Bool)]) async {
        guard !jobs.isEmpty, !isBusy else { return }
        guard let key = Keychain.read(.qwen) else {
            errorMessage = "Add your Qwen API key in Settings to draw photos."
            return
        }
        let settings = ProviderSettings.load()
        let qwen = QwenImageClient(apiKey: key, model: settings.qwenModel, baseURL: settings.qwenBaseURL)
        let planDate = plan?.date

        phase = .drawing(done: 0, total: jobs.count)
        var failures: [String] = []
        await withTaskGroup(of: (String, Result<Data, Error>).self) { group in
            for job in jobs {
                let size = job.isStep ? qwen.stepSize : qwen.heroSize
                group.addTask {
                    do {
                        return (job.key, .success(try await qwen.imageData(prompt: job.prompt, size: size)))
                    } catch {
                        return (job.key, .failure(error))
                    }
                }
            }
            var done = 0
            for await (imageKey, result) in group {
                done += 1
                phase = .drawing(done: done, total: jobs.count)
                switch result {
                case .success(let data):
                    // Ignore photos for a plan that was replaced while they were drawing.
                    guard plan?.date == planDate else { continue }
                    images[imageKey] = data
                    try? data.write(to: imageURL(imageKey))
                case .failure(let error):
                    failures.append(error.localizedDescription)
                }
            }
        }
        phase = .idle
        if let first = failures.first {
            errorMessage = "\(failures.count) of \(jobs.count) photos failed. \(first)"
        }
    }

    // MARK: - Storage

    private func imageURL(_ key: String) -> URL {
        imageDirectory.appendingPathComponent("\(key).png")
    }

    private func replacePlan(with newPlan: MealPlan) throws {
        try newPlan.encoded().write(to: planURL, options: .atomic)
        for file in (try? FileManager.default.contentsOfDirectory(at: imageDirectory, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: file)
        }
        images = [:]
        plan = newPlan
        isSample = false
    }

    private func loadSaved() {
        if let data = try? Data(contentsOf: planURL),
           let saved = try? MealPlan.decode(from: data),
           MealPlanRules.violations(in: saved).isEmpty {
            plan = saved
            isSample = false
            for dish in saved.dishes {
                let keys = [Self.heroKey(dish)] + dish.steps.map { Self.stepKey(dish, $0) }
                for key in keys {
                    if let data = try? Data(contentsOf: imageURL(key)) {
                        images[key] = data
                    }
                }
            }
            return
        }
        do {
            plan = try MealPlanLoader.loadSample()
            isSample = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
