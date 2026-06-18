import Foundation
import MLXLMCommon
import MLXLLM
import Hub

/// MLX-backed meeting title generator using local LLM.
///
/// Downloads a small model (SmolLM-135M-Instruct-4bit, ~100MB) on first use,
/// then generates titles locally. Falls back to static titles on any error/timeout.
@MainActor
final class MLXTitleGenerator: MeetingTitleGenerator {

    private let staticGenerator = StaticTitleGeneratorActor()
    private var modelContainer: ModelContainer?
    private var isLoading = false

    // Use the pre-defined SmolLM-135M configuration from MLXLLM
    private let modelConfig = LLMRegistry.smolLM_135M_4bit

    // Generation parameters - maxTokens must come first
    private let generateParams = GenerateParameters(
        maxTokens: 16,
        temperature: 0.8
    )

    /// Generates a fictitious meeting title using local MLX model.
    /// Falls back to static titles if model fails or isn't ready.
    func generateTitle() async -> String {
        // Ensure model is loaded (downloads on first call, caches thereafter)
        guard await ensureModelLoaded() else {
            return await staticGenerator.generateTitle()
        }

        guard let container = modelContainer else {
            return await staticGenerator.generateTitle()
        }

        // System prompt for meeting title generation
        let systemPrompt = """
            You generate harmless, amusing, fictitious meeting titles for a calendar event.
            The user is actually going surfing. Titles should be 2-5 words, wholesome, slightly
            absurd, and believable as a fake meeting. No quotes, no preamble, just the title.
            Examples: "Underwater Basket Weaving", "Competitive Cloud Gazing", "Teaching My Goldfish Tricks"
            """

        let prompt = "User: Generate a meeting title.\nAssistant:"

        do {
            let session = ChatSession(
                container,
                instructions: systemPrompt,
                generateParameters: generateParams
            )
            let response = try await session.respond(to: prompt)
            
            // Clean up response - take first line, trim whitespace
            let cleaned = response
                .split(separator: "\n")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            // If response is empty or too long, fall back
            if cleaned.isEmpty || cleaned.count > 50 {
                return await staticGenerator.generateTitle()
            }
            
            return cleaned
        } catch {
            // Any error -> silent fallback to static
            return await staticGenerator.generateTitle()
        }
    }

    /// Ensures the model is downloaded and loaded.
    /// Returns true if successful, false if failed (caller should use fallback).
    private func ensureModelLoaded() async -> Bool {
        if modelContainer != nil { return true }
        if isLoading { return false } // Avoid concurrent loads

        isLoading = true
        defer { isLoading = false }

        do {
            // This downloads the model on first run, uses cache thereafter
            let container = try await loadModelContainer(configuration: modelConfig)
            modelContainer = container
            return true
        } catch {
            // Download or load failed - will fall back to static
            return false
        }
    }
}