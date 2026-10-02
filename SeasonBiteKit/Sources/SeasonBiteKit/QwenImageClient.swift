import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Renders the plan's photo prompts with Qwen-Image (Alibaba Cloud Model Studio / DashScope).
public struct QwenImageClient: Sendable {
    public enum ImageError: LocalizedError, Equatable {
        case noImage(String)

        public var errorDescription: String? {
            switch self {
            case .noImage(let body):
                return "Qwen returned no image: \(body.prefix(300))"
            }
        }
    }

    public static let defaultModel = "qwen-image-2.0"
    /// China (Beijing) region. Workspace domains look like https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/api/v1
    public static let defaultBaseURL = URL(string: "https://dashscope.aliyuncs.com/api/v1")!
    static let negativePrompt = "cartoon, illustration, 3D render, anime, text, watermark, logo, hands, blurry, low quality"

    public var apiKey: String
    public var model: String
    public var baseURL: URL
    var transport: HTTPTransport

    public init(
        apiKey: String,
        model: String = QwenImageClient.defaultModel,
        baseURL: URL = QwenImageClient.defaultBaseURL,
        transport: HTTPTransport = URLSessionTransport()
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.transport = transport
    }

    /// Square size for dish cards, 4:3 for steps. The 2.0+ models use larger sizes than the original ones.
    public var heroSize: String {
        isLargeSizeModel ? "2048*2048" : "1328*1328"
    }

    public var stepSize: String {
        isLargeSizeModel ? "2368*1728" : "1472*1104"
    }

    private var isLargeSizeModel: Bool {
        !["qwen-image", "qwen-image-plus", "qwen-image-max"].contains(model)
    }

    /// Generates one image and downloads it. Qwen's image links expire after 24 hours, so keep the bytes.
    public func imageData(prompt: String, size: String) async throws -> Data {
        let url = try await imageURL(prompt: prompt, size: size)
        let (data, response) = try await transport.send(URLRequest(url: url, timeoutInterval: 120))
        try checkStatus(data, response, provider: "Qwen image download")
        return data
    }

    public func imageURL(prompt: String, size: String) async throws -> URL {
        let body = GenerationRequest(
            model: model,
            input: .init(messages: [.init(role: "user", content: [.init(text: prompt)])]),
            parameters: .init(negativePrompt: Self.negativePrompt, promptExtend: false, watermark: false, size: size)
        )
        let request = try jsonRequest(
            url: baseURL.appendingPathComponent("services/aigc/multimodal-generation/generation"),
            apiKey: apiKey,
            body: body,
            timeout: 300
        )
        let (data, response) = try await transport.send(request)
        try checkStatus(data, response, provider: "Qwen")
        let decoded = try? JSONDecoder().decode(GenerationResponse.self, from: data)
        let image = decoded?.output.choices.first?.message.content.compactMap(\.image).first
        guard let image, let url = URL(string: image) else {
            throw ImageError.noImage(String(decoding: data, as: UTF8.self))
        }
        return url
    }

    // MARK: - Wire format

    struct GenerationRequest: Encodable {
        struct Input: Encodable {
            struct Message: Encodable {
                struct Part: Encodable {
                    var text: String
                }

                var role: String
                var content: [Part]
            }

            var messages: [Message]
        }

        struct Parameters: Encodable {
            var negativePrompt: String
            var promptExtend: Bool
            var watermark: Bool
            var size: String

            enum CodingKeys: String, CodingKey {
                case watermark, size
                case negativePrompt = "negative_prompt"
                case promptExtend = "prompt_extend"
            }
        }

        var model: String
        var input: Input
        var parameters: Parameters
    }

    struct GenerationResponse: Decodable {
        struct Output: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    struct Part: Decodable {
                        var image: String?
                    }

                    var content: [Part]
                }

                var message: Message
            }

            var choices: [Choice]
        }

        var output: Output
    }
}
