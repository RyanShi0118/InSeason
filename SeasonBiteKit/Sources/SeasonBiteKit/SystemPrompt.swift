import Foundation

/// Builds the planner's system prompt from the files in prompts/ and schema/.
public enum SystemPrompt {
    /// The prompt file has a short note for developers above the first `---`; that part is dropped.
    public static func make(promptMarkdown: String, schemaJSON: String) -> String {
        var body = Substring(promptMarkdown)
        if let divider = promptMarkdown.range(of: "\n---\n") {
            body = promptMarkdown[divider.upperBound...]
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n\nThe JSON Schema your json reply must validate against:\n\n"
            + schemaJSON
    }
}
