import Foundation

/// MLX-backed meeting title generator (stub - MLX integration deferred).
///
/// When MLX Swift LLM packages stabilize, this will:
/// 1. Download a small model (e.g., SmolLM2-360M-Instruct-4bit, ~300MB)
/// 2. Generate titles locally using a system prompt
/// 3. Fall back to static titles on error/timeout
///
/// Current implementation: delegates to StaticTitleGeneratorActor for immediate functionality.
@MainActor
final class MLXTitleGenerator: MeetingTitleGenerator {

    private let staticGenerator = StaticTitleGeneratorActor()

    /// Generates a fictitious meeting title.
    /// Currently delegates to static generator; MLX integration pending package stabilization.
    func generateTitle() async -> String {
        // TODO(T8-T11): Implement MLX local LLM generation
        // - Add MLX Swift + MLXLM dependencies (see project.yml.template)
        // - Download SmolLM2-360M-Instruct-4bit or Llama-3.2-1B-Instruct-4bit on first use
        // - Use system prompt for "harmless, amusing fictitious meeting titles"
        // - Generation params: temp=0.9, maxTokens=16, stop at newline/period
        // - Silent fallback to static on any error
        return await staticGenerator.generateTitle()
    }
}

/// Template for MLX dependencies (re-add when packages stabilize)
///
/// ```yaml
/// packages:
///   MLX:
///     url: https://github.com/ml-explore/mlx-swift.git
///     from: "0.20.0"
///   MLXLM:
///     url: https://github.com/ml-explore/mlx-swift-lm.git
///     revision: "<working-version>"
///
/// targets:
///   Swell:
///     dependencies:
///       - package: GRDB
///       - package: MLX
///       - product: LLM
///         package: MLXLM
/// ```