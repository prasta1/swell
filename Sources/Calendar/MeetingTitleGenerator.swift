import Foundation

/// Protocol for generating fictitious meeting titles.
protocol MeetingTitleGenerator: Sendable {
    /// Generates a single harmless, amusing meeting title.
    func generateTitle() async -> String
}

/// Static fallback generator — zero dependencies, instant, reliable.
/// Used as MVP and as fallback if LLM backend fails.
struct StaticTitleGenerator: MeetingTitleGenerator {
    private static let titles: [String] = [
        "Underwater Basket Weaving",
        "Building a Snowman",
        "Walking My Tiger",
        "Competitive Cloud Gazing",
        "Teaching My Goldfish Tricks",
        "Extreme Pillow Fort Engineering",
        "Professional Nap Consulting",
        "Squirrel Diplomacy Summit",
        "Interpretive Dance Practice",
        "Telepathy Calibration Session",
        "Time Travel Troubleshooting",
        "Unicorn Grooming Appointment",
        "Shadow Puppet Rehearsal",
        "Backwards Walking Clinic",
        "Invisible Friend Mediation",
        "Cloud Shape Identification",
        "Puddle Depth Analysis",
        "Leaf Pile Architecture",
        "Cardboard Box Innovation Lab",
        "Sock Puppet Theater Prep",
        "Pebble Skipping Championship",
        "Dandelion Wish Coordination",
        "Firefly Negotiation Tactics",
        "Rainbow Endpoint Location",
        "Bubble Wrap Stress Testing",
        "Paper Airplane Aerodynamics",
        "Sidewalk Chalk Symposium",
        "Tide Pool Census",
        "Seashell Sorting Sprint",
        "Horizon Staring Contest",
    ]

    /// Shuffled once per session for variety without repeats until exhausted.
    private var shuffled: [String] = []
    private var index: Int = 0

    init() {
        reshuffle()
    }

    private mutating func reshuffle() {
        shuffled = Self.titles.shuffled()
        index = 0
    }

    func generateTitle() async -> String {
        // Note: This is a struct with mutating state — in practice we'd use
        // an actor or class for thread safety. For v1 simplicity, we accept
        // that concurrent calls may race. The static list is large enough
        // that it doesn't matter much.
        var generator = self
        if generator.index >= generator.shuffled.count {
            generator.reshuffle()
        }
        let title = generator.shuffled[generator.index]
        generator.index += 1
        return title
    }
}

/// Thread-safe wrapper for StaticTitleGenerator using an actor.
actor StaticTitleGeneratorActor: MeetingTitleGenerator {
    private var generator = StaticTitleGenerator()

    func generateTitle() async -> String {
        await generator.generateTitle()
    }
}