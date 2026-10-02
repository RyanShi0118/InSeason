import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Asks DeepSeek for a meal plan and only returns one that passes every SeasonBite rule.
///
/// If a reply breaks a rule, DeepSeek gets the list of problems and another try.
public struct DeepSeekPlanner: Sendable {
    public enum PlannerError: LocalizedError, Equatable {
        case truncated
        case invalidPlan([String])

        public var errorDescription: String? {
            switch self {
            case .truncated:
                return "DeepSeek's reply was cut off before the plan finished."
            case .invalidPlan(let errors):
                return "DeepSeek could not produce a plan that follows the rules:\n" + errors.joined(separator: "\n")
            }
        }
    }

    public static let defaultModel = "deepseek-v4-pro"
    public static let defaultBaseURL = URL(string: "https://api.deepseek.com")!

    public var apiKey: String
    public var model: String
    public var baseURL: URL
    public var systemPrompt: String
    public var maxAttempts: Int
    public var maxTokens: Int
    var transport: HTTPTransport

    public init(
        apiKey: String,
        systemPrompt: String,
        model: String = DeepSeekPlanner.defaultModel,
        baseURL: URL = DeepSeekPlanner.defaultBaseURL,
        maxAttempts: Int = 2,
        maxTokens: Int = 32000,
        transport: HTTPTransport = URLSessionTransport()
    ) {
        self.apiKey = apiKey
        self.systemPrompt = systemPrompt
        self.model = model
        self.baseURL = baseURL
        self.maxAttempts = maxAttempts
        self.maxTokens = maxTokens
        self.transport = transport
    }

    /// - Parameter date: ISO date, e.g. "2026-10-02".
    public func plan(date: String, household: Household) async throws -> MealPlan {
        var messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: Self.userRequest(date: date, household: household)),
        ]
        var errors: [String] = []

        for _ in 0..<maxAttempts {
            let reply = try await complete(messages)
            if reply.finishReason == "length" {
                throw PlannerError.truncated
            }
            guard let content = reply.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                // DeepSeek's JSON mode occasionally returns empty content; ask again unchanged.
                errors = ["DeepSeek returned an empty reply"]
                continue
            }

            switch Self.check(content, date: date, household: household) {
            case .success(let plan):
                return plan
            case .failure(let problems):
                errors = problems.errors
                messages.append(ChatMessage(role: "assistant", content: content))
                messages.append(ChatMessage(
                    role: "user",
                    content: "That plan breaks these rules:\n"
                        + errors.map { "- \($0)" }.joined(separator: "\n")
                        + "\nFix every one and reply with the complete corrected json object only."
                ))
            }
        }
        throw PlannerError.invalidPlan(errors)
    }

    // MARK: - Checking a reply

    struct Problems: Error {
        var errors: [String]
    }

    static func userRequest(date: String, household: Household) -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let householdJSON = (try? encoder.encode(household)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return """
        Plan one family dinner for \(date).
        Household: \(householdJSON)
        Copy the date and household into the plan exactly as given. Reply with the json object only.
        """
    }

    /// Parses a reply, tolerating a ```json fence or stray text around the object.
    static func check(_ content: String, date: String, household: Household) -> Result<MealPlan, Problems> {
        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"), start < end else {
            return .failure(Problems(errors: ["reply is not a json object"]))
        }
        let plan: MealPlan
        do {
            plan = try MealPlan.decode(from: Data(content[start...end].utf8))
        } catch {
            return .failure(Problems(errors: ["reply does not match the meal plan schema: \(describe(error))"]))
        }
        var errors = MealPlanRules.violations(in: plan)
        if errors.isEmpty {
            errors = requestMismatches(plan, date: date, household: household)
        }
        return errors.isEmpty ? .success(plan) : .failure(Problems(errors: errors))
    }

    static func requestMismatches(_ plan: MealPlan, date: String, household: Household) -> [String] {
        var errors: [String] = []
        if plan.date != date {
            errors.append("date is \(plan.date), requested \(date)")
        }
        if plan.household.adults != household.adults {
            errors.append("household.adults is \(plan.household.adults), requested \(household.adults)")
        }
        let got = plan.household.children.map(\.ageYears).sorted()
        let want = household.children.map(\.ageYears).sorted()
        if got != want {
            errors.append("children's ages are \(got), requested \(want)")
        }
        return errors
    }

    static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return "\(error)" }
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: "/")
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "missing \(key.stringValue) at \(path(context))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return "\(context.debugDescription) at \(path(context))"
        @unknown default:
            return "\(error)"
        }
    }

    // MARK: - HTTP

    struct ChatMessage: Codable, Equatable {
        var role: String
        var content: String
    }

    struct ChatRequest: Encodable {
        struct ResponseFormat: Encodable {
            var type = "json_object"
        }

        var model: String
        var messages: [ChatMessage]
        var responseFormat = ResponseFormat()
        var maxTokens: Int
        var stream = false

        enum CodingKeys: String, CodingKey {
            case model, messages, stream
            case responseFormat = "response_format"
            case maxTokens = "max_tokens"
        }
    }

    struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                var content: String?
            }

            var message: Message
            var finishReason: String?

            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }

        var choices: [Choice]
    }

    struct Reply {
        var content: String?
        var finishReason: String?
    }

    func complete(_ messages: [ChatMessage]) async throws -> Reply {
        let body = ChatRequest(model: model, messages: messages, maxTokens: maxTokens)
        // Thinking-mode replies for a full plan can take a few minutes.
        let request = try jsonRequest(
            url: baseURL.appendingPathComponent("chat/completions"),
            apiKey: apiKey,
            body: body,
            timeout: 600
        )
        let (data, response) = try await transport.send(request)
        try checkStatus(data, response, provider: "DeepSeek")
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let choice = decoded.choices.first
        return Reply(content: choice?.message.content, finishReason: choice?.finishReason)
    }
}
