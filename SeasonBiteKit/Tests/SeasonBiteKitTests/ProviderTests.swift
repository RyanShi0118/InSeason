import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import SeasonBiteKit

/// Returns canned responses in order and records every request.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(Int, Data)]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [(Int, Data)]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        let (status, data) = responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }

    func body(_ index: Int) throws -> [String: Any] {
        let data = try XCTUnwrap(requests[index].httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func sampleText() throws -> String {
    try String(contentsOf: repoRoot.appendingPathComponent("examples/2026-10-01_family_dinner.json"), encoding: .utf8)
}

private func brokenSampleText() throws -> String {
    var plan = try JSONSerialization.jsonObject(with: Data(sampleText().utf8)) as! [String: Any]
    var dishes = plan["dishes"] as! [[String: Any]]
    let index = dishes.firstIndex { $0["id"] as? String == "golden_sour_tofu_caltrop" }!
    var steps = dishes[index]["steps"] as! [[String: Any]]
    steps[1]["portion"] = "adult_only"
    dishes[index]["steps"] = steps
    plan["dishes"] = dishes
    return String(decoding: try JSONSerialization.data(withJSONObject: plan), as: UTF8.self)
}

private func chatReply(_ content: String, finishReason: String = "stop") throws -> (Int, Data) {
    let message: [String: Any] = ["role": "assistant", "content": content]
    let choice: [String: Any] = ["message": message, "finish_reason": finishReason]
    let body: [String: Any] = ["choices": [choice]]
    return (200, try JSONSerialization.data(withJSONObject: body))
}

private let household = Household(adults: 2, children: [Child(ageYears: 4, allergies: [])])

final class DeepSeekPlannerTests: XCTestCase {
    private func planner(_ transport: FakeTransport) -> DeepSeekPlanner {
        DeepSeekPlanner(apiKey: "sk-test", systemPrompt: "SYSTEM json", transport: transport)
    }

    func testValidReplyIsReturned() async throws {
        let transport = FakeTransport([try chatReply(sampleText())])
        let plan = try await planner(transport).plan(date: "2026-10-01", household: household)
        XCTAssertEqual(plan.dishes.count, 4)

        let request = transport.requests[0]
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        let body = try transport.body(0)
        XCTAssertEqual(body["model"] as? String, "deepseek-v4-pro")
        XCTAssertEqual((body["response_format"] as? [String: String])?["type"], "json_object")
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertTrue(messages[1]["content"]!.contains("Plan one family dinner for 2026-10-01"))
        XCTAssertTrue(messages[1]["content"]!.contains("\"age_years\":4"))
    }

    func testFencedReplyIsAccepted() async throws {
        let transport = FakeTransport([try chatReply("```json\n\(try sampleText())\n```")])
        _ = try await planner(transport).plan(date: "2026-10-01", household: household)
    }

    func testRuleBreakGetsARepairRound() async throws {
        let broken = try brokenSampleText()
        let transport = FakeTransport([try chatReply(broken), try chatReply(sampleText())])
        _ = try await planner(transport).plan(date: "2026-10-01", household: household)

        let messages = try XCTUnwrap(try transport.body(1)["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 4)
        XCTAssertEqual(messages[2]["role"], "assistant")
        XCTAssertTrue(messages[3]["content"]!.contains("adult-only step 2 comes before"))
    }

    func testStillBrokenAfterRepairThrows() async throws {
        let broken = try brokenSampleText()
        let transport = FakeTransport([try chatReply(broken), try chatReply(broken)])
        do {
            _ = try await planner(transport).plan(date: "2026-10-01", household: household)
            XCTFail("expected invalidPlan")
        } catch DeepSeekPlanner.PlannerError.invalidPlan(let errors) {
            XCTAssertTrue(errors.contains { $0.contains("adult-only step 2") }, "\(errors)")
        }
    }

    func testWrongDateIsRejected() async throws {
        let transport = FakeTransport([try chatReply(sampleText()), try chatReply(sampleText())])
        do {
            _ = try await planner(transport).plan(date: "2026-10-02", household: household)
            XCTFail("expected invalidPlan")
        } catch DeepSeekPlanner.PlannerError.invalidPlan(let errors) {
            XCTAssertEqual(errors, ["date is 2026-10-01, requested 2026-10-02"])
        }
    }

    func testEmptyReplyIsRetriedUnchanged() async throws {
        let transport = FakeTransport([try chatReply(""), try chatReply(sampleText())])
        _ = try await planner(transport).plan(date: "2026-10-01", household: household)
        let messages = try XCTUnwrap(try transport.body(1)["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 2)
    }

    func testTruncatedReplyThrows() async throws {
        let transport = FakeTransport([try chatReply("{\"date\":", finishReason: "length")])
        do {
            _ = try await planner(transport).plan(date: "2026-10-01", household: household)
            XCTFail("expected truncated")
        } catch DeepSeekPlanner.PlannerError.truncated {}
    }

    func testHTTPErrorSurfaces() async throws {
        let transport = FakeTransport([(401, Data("{\"error\":\"bad key\"}".utf8))])
        do {
            _ = try await planner(transport).plan(date: "2026-10-01", household: household)
            XCTFail("expected HTTP error")
        } catch let error as ProviderHTTPError {
            XCTAssertEqual(error.status, 401)
            XCTAssertEqual(error.provider, "DeepSeek")
        }
    }

    func testSystemPromptDropsDeveloperNote() throws {
        let markdown = try String(contentsOf: repoRoot.appendingPathComponent("prompts/seasonbite_chef_system.md"), encoding: .utf8)
        let prompt = SystemPrompt.make(promptMarkdown: markdown, schemaJSON: "{\"title\": \"schema\"}")
        XCTAssertTrue(prompt.hasPrefix("You are the Executive Pediatric/Adult Dietitian"))
        XCTAssertTrue(prompt.contains("MANDATORY dual-prep rule"))
        XCTAssertTrue(prompt.hasSuffix("{\"title\": \"schema\"}"))
    }
}

final class QwenImageClientTests: XCTestCase {
    func testGeneratesAndDownloads() async throws {
        let message: [String: Any] = [
            "role": "assistant",
            "content": [["image": "https://example.com/dish.png?Expires=1"]],
        ]
        let choice: [String: Any] = ["finish_reason": "stop", "message": message]
        let output: [String: Any] = ["choices": [choice]]
        let generation: [String: Any] = ["output": output, "request_id": "abc"]
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let transport = FakeTransport([(200, try JSONSerialization.data(withJSONObject: generation)), (200, png)])
        let client = QwenImageClient(apiKey: "sk-qwen", transport: transport)

        let data = try await client.imageData(prompt: "steamed perch", size: client.heroSize)
        XCTAssertEqual(data, png)

        XCTAssertEqual(
            transport.requests[0].url?.absoluteString,
            "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation"
        )
        let body = try transport.body(0)
        XCTAssertEqual(body["model"] as? String, "qwen-image-2.0")
        let parameters = try XCTUnwrap(body["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["size"] as? String, "2048*2048")
        XCTAssertEqual(parameters["watermark"] as? Bool, false)
        XCTAssertEqual(transport.requests[1].url?.absoluteString, "https://example.com/dish.png?Expires=1")
    }

    func testOriginalModelsUseSmallerSizes() {
        let client = QwenImageClient(apiKey: "k", model: "qwen-image-plus")
        XCTAssertEqual(client.heroSize, "1328*1328")
        XCTAssertEqual(client.stepSize, "1472*1104")
    }

    func testErrorBodyIsReported() async throws {
        let transport = FakeTransport([(200, Data("{\"code\":\"DataInspectionFailed\"}".utf8))])
        let client = QwenImageClient(apiKey: "k", transport: transport)
        do {
            _ = try await client.imageURL(prompt: "x", size: client.heroSize)
            XCTFail("expected noImage")
        } catch QwenImageClient.ImageError.noImage(let body) {
            XCTAssertTrue(body.contains("DataInspectionFailed"))
        }
    }
}

final class MealPlanEncodingTests: XCTestCase {
    func testRoundTrip() throws {
        let plan = try MealPlan.decode(from: Data(sampleText().utf8))
        XCTAssertEqual(try MealPlan.decode(from: plan.encoded()), plan)
    }
}
